#!/bin/bash
# ==========================================================================
# KernelSU-Next v3.1.0 + SUSFS v2.1 Compatibility Fixup
# ==========================================================================
# The upstream SUSFS patch targets official KernelSU, not KernelSU-Next.
# This script manually applies the failed hunks, adapted for KernelSU-Next's
# code structure. It preserves the existing hooking architecture.
# ==========================================================================
set -e

KSU_KERNEL="$1"
if [ -z "$KSU_KERNEL" ] || [ ! -d "$KSU_KERNEL" ]; then
    echo "Usage: $0 <path-to-kernelsu-next/kernel>"
    exit 1
fi

echo "[SUSFS-Fixup] Starting compatibility fixups for KernelSU-Next + SUSFS v2.1..."

# ------------------------------------------------------------------
# 1. Kbuild: The patch tried to REMOVE hook objects (lsm_hook, etc.)
#    We must NOT do that — KernelSU-Next needs them. No changes needed
#    here since the hunk correctly failed. The existing Kbuild is fine.
# ------------------------------------------------------------------
echo "[SUSFS-Fixup] 1/8 Kbuild: No changes needed (keeping existing hook objects)"

# ------------------------------------------------------------------
# 2. Makefile: Add SUSFS version detection (append at end before last line)
# ------------------------------------------------------------------
echo "[SUSFS-Fixup] 2/8 Makefile: Adding SUSFS version detection..."
MAKEFILE="$KSU_KERNEL/Makefile"
if [ -f "$MAKEFILE" ] && ! grep -q "SUSFS_VERSION" "$MAKEFILE" 2>/dev/null; then
    # Insert before the last "# Keep a new line" comment
    sed -i '/^# Keep a new line/i \
## For susfs stuff ##\
ifeq ($(shell test -e $(srctree)/fs/susfs.c; echo $$?),0)\
$(eval SUSFS_VERSION=$(shell cat $(srctree)/include/linux/susfs.h | grep -E '"'"'^#define SUSFS_VERSION'"'"' | cut -d'"'"' '"'"' -f3 | sed '"'"'s/"//g'"'"'))\
$(info )\
$(info -- SUSFS_VERSION: $(SUSFS_VERSION))\
else\
$(info -- You have not integrated susfs in your kernel yet.)\
$(info -- Read: https://gitlab.com/simonpunk/susfs4ksu)\
endif\
' "$MAKEFILE"
fi

# ------------------------------------------------------------------
# 3. core/init.c: Add susfs_init() call + include if patch failed.
#    The SUSFS patch's hunk 4 (susfs_init) succeeds but hunk 1
#    (#include <linux/susfs.h>) fails. Add the include if missing.
#    Keep ksu_late_loaded, keep existing hooking.
# ------------------------------------------------------------------
echo "[SUSFS-Fixup] 3/8 core/init.c: Ensuring susfs include + init call..."
INIT_C="$KSU_KERNEL/core/init.c"

# Add #include <linux/susfs.h> if missing (hunk 1 fails)
if ! grep -q "linux/susfs.h" "$INIT_C" 2>/dev/null; then
    sed -i '/#include <linux\/workqueue.h>/a #include <linux/susfs.h>' "$INIT_C"
fi

# susfs_init() should already be added by the patch (hunk 4 succeeds).
# Double-check and add if somehow missing.
if ! grep -q "susfs_init()" "$INIT_C" 2>/dev/null; then
    # Add before the second #ifdef MODULE (end of kernelsu_init)
    sed -i '/ksu_file_wrapper_init/a\\n\tsusfs_init();' "$INIT_C"
fi

# ------------------------------------------------------------------
# 4. feature/sucompat.c: Add ksu_handle_execveat_init() — critical for
#    SUSFS process marking during init. This is the most important fix.
# ------------------------------------------------------------------
echo "[SUSFS-Fixup] 4/8 feature/sucompat.c: Adding ksu_handle_execveat_init()..."
SUCOMPAT_C="$KSU_KERNEL/feature/sucompat.c"

# Add required SUSFS includes
if ! grep -q "linux/susfs_def.h" "$SUCOMPAT_C" 2>/dev/null; then
    sed -i '/#include <linux\/ptrace.h>/a #include <linux/susfs_def.h>\n#include <linux/namei.h>' "$SUCOMPAT_C"
fi

# Add ksu_handle_execveat_init function if it doesn't exist
if ! grep -q "ksu_handle_execveat_init" "$SUCOMPAT_C" 2>/dev/null; then
    cat >> "$SUCOMPAT_C" << 'SUCOMPAT_EOF'

#ifdef CONFIG_KSU_SUSFS
/*
 * ksu_handle_execveat_init — SUSFS init process exec hook
 * return 0 -> No further checks should be required afterwards
 * return non-zero -> Further checks should be continued afterwards
 */
int ksu_handle_execveat_init(struct filename *filename,
    struct user_arg_ptr *argv_user, struct user_arg_ptr *envp_user)
{
    if (current->pid != 1 && is_init(get_current_cred())) {
        if (unlikely(strcmp(filename->name, KSUD_PATH) == 0)) {
            pr_info("hook_manager: escape to root for init executing ksud: %d\n",
                current->pid);
            escape_to_root_for_init();
            return 0;
        } else if (likely(strstr(filename->name, "/app_process") == NULL &&
                    strstr(filename->name, "/adbd") == NULL) &&
                    !susfs_is_current_proc_umounted())
        {
            pr_info("susfs: mark no sucompat checks for pid: '%d', exec: '%s'\n",
                current->pid, filename->name);
            susfs_set_current_proc_umounted();
            return 0;
        }
        return 0;
    }
    return -EINVAL;
}
#endif /* CONFIG_KSU_SUSFS */
SUCOMPAT_EOF
fi

# ------------------------------------------------------------------
# 5. feature/sucompat.h: Add ksu_handle_execveat_init declaration
# ------------------------------------------------------------------
echo "[SUSFS-Fixup] 5/8 feature/sucompat.h: Adding declarations..."
SUCOMPAT_H="$KSU_KERNEL/feature/sucompat.h"

if ! grep -q "ksu_handle_execveat_init" "$SUCOMPAT_H" 2>/dev/null; then
    sed -i '/^#endif/i \
#ifdef CONFIG_KSU_SUSFS\
#include <linux/fs.h>\
#include "runtime/ksud.h"\
int ksu_handle_execveat_init(struct filename *filename,\
    struct user_arg_ptr *argv_user, struct user_arg_ptr *envp_user);\
#endif' "$SUCOMPAT_H"
fi

# Also add version include if missing
if ! grep -q "linux/version.h" "$SUCOMPAT_H" 2>/dev/null; then
    sed -i '/#include <linux\/types.h>/a #include <linux/version.h>' "$SUCOMPAT_H"
fi

# ------------------------------------------------------------------
# 6. feature/kernel_umount.c: Remove excessive UID/zygote checks that
#    SUSFS replaces with its own mount-hiding logic. The SUSFS setuid_hook
#    already checks isolated_process and directs them to do_umount.
# ------------------------------------------------------------------
echo "[SUSFS-Fixup] 6/8 feature/kernel_umount.c: Adapting for SUSFS mount handling..."
KUMOUNT_C="$KSU_KERNEL/feature/kernel_umount.c"
# No changes needed here — the SUSFS setuid_hook.c already handles the
# isolated process check with "goto do_umount". The kernel_umount.c
# checks are still valid for its own callers. Keeping as-is is safe.

# ------------------------------------------------------------------
# 7. hook/setuid_hook.c + syscall_event_bridge.c: Fix setresuid hook
#    The SUSFS patch changed ksu_handle_setresuid from (old_uid, new_uid)
#    to (ruid, euid, suid). syscall_event_bridge.c still calls the old API.
# ------------------------------------------------------------------
echo "[SUSFS-Fixup] 7/8 hook/setuid_hook.c: Adding do_umount label + fixing setresuid call..."
SETUID_HOOK_C="$KSU_KERNEL/hook/setuid_hook.c"
BRIDGE_C="$KSU_KERNEL/hook/syscall_event_bridge.c"

# Add tp_marker.h include (provides ksu_set_task_tracepoint_flag inline)
if [ -f "$SETUID_HOOK_C" ] && grep -q "ksu_set_task_tracepoint_flag" "$SETUID_HOOK_C" 2>/dev/null; then
    if ! grep -q "hook/tp_marker.h" "$SETUID_HOOK_C" 2>/dev/null; then
        sed -i '/#include "hook\/setuid_hook.h"/a #include "hook/tp_marker.h"' "$SETUID_HOOK_C"
    fi
fi

# Add do_umount label before ksu_handle_umount call
if [ -f "$SETUID_HOOK_C" ] && grep -q "goto do_umount;" "$SETUID_HOOK_C" 2>/dev/null; then
    if ! grep -q "do_umount:" "$SETUID_HOOK_C" 2>/dev/null; then
        sed -i '/ksu_handle_umount/i\\ndo_umount:' "$SETUID_HOOK_C"
    fi
fi

# Fix syscall_event_bridge.c: ksu_handle_setresuid call signature
# SUSFS changed it from (old_uid, new_uid) to (ruid, euid, suid)
# We update the caller to extract all 3 args from pt_regs
if [ -f "$BRIDGE_C" ] && grep -q "ksu_handle_setresuid(old_uid, current_uid().val)" "$BRIDGE_C" 2>/dev/null; then
    echo "[SUSFS-Fixup] Fixing ksu_hook_setresuid in syscall_event_bridge.c..."
    sed -i 's/ksu_handle_setresuid(old_uid, current_uid()\.val);/{\
        uid_t ruid = PT_REGS_PARM1(regs);\
        uid_t euid = PT_REGS_PARM2(regs);\
        uid_t suid = PT_REGS_PARM3(regs);\
        ksu_handle_setresuid(ruid, euid, suid);\
    }/' "$BRIDGE_C"
fi

# ------------------------------------------------------------------
# 8. supercall/supercall.c: Add ksu_supercall_reboot_handler()
#    The SUSFS dispatch.c calls this for KSU fd installation.
#    We keep the existing kprobe AND add this function (the kprobe
#    handles legacy callers, this function handles the new SUSFS path).
# ------------------------------------------------------------------
echo "[SUSFS-Fixup] 8/8 supercall/supercall.c: Adding ksu_supercall_reboot_handler..."
SUPERCALL_C="$KSU_KERNEL/supercall/supercall.c"
SUPERCALL_H="$KSU_KERNEL/supercall/supercall.h"

# Add the function implementation to supercall.c
if ! grep -q "ksu_supercall_reboot_handler" "$SUPERCALL_C" 2>/dev/null; then
    cat >> "$SUPERCALL_C" << 'SUPERCALL_EOF'

/* SUSFS compatibility: ksu_handle_sys_reboot in dispatch.c calls this
 * for KSU fd installation via the tracepoint/ioctl path. */
int ksu_supercall_reboot_handler(void __user **arg)
{
    struct ksu_install_fd_tw *tw;

    tw = kzalloc(sizeof(*tw), GFP_KERNEL);
    if (!tw)
        return 0;

    tw->outp = (int __user *)(*arg);
    tw->cb.func = ksu_install_fd_tw_func;

    if (task_work_add(current, &tw->cb, TWA_RESUME)) {
        kfree(tw);
        pr_warn("install fd add task_work failed\n");
    }

    return 0;
}
SUPERCALL_EOF
fi

# Add declaration in supercall.h if missing
if [ -f "$SUPERCALL_H" ] && ! grep -q "ksu_supercall_reboot_handler" "$SUPERCALL_H" 2>/dev/null; then
    sed -i '/int ksu_install_fd(void);/a int ksu_supercall_reboot_handler(void __user **arg);' "$SUPERCALL_H"
fi

# ------------------------------------------------------------------
# Extra: Fix ksu_late_loaded — the patch removes it from ksu.h but
# the existing KernelSU-Next code still uses it everywhere
# ------------------------------------------------------------------
echo "[SUSFS-Fixup] Extra: Restoring ksu_late_loaded if needed..."
KSU_H="$KSU_KERNEL/include/ksu.h"
if grep -q "ksu_late_loaded" "$KSU_KERNEL/core/init.c" 2>/dev/null; then
    if ! grep -q "bool ksu_late_loaded" "$KSU_KERNEL/core/init.c" 2>/dev/null; then
        sed -i '/^struct cred \*ksu_cred;/a bool ksu_late_loaded;' "$KSU_KERNEL/core/init.c"
    fi
    if ! grep -q "extern bool ksu_late_loaded" "$KSU_H" 2>/dev/null; then
        sed -i '/^extern struct cred \*ksu_cred;/a extern bool ksu_late_loaded;' "$KSU_H"
    fi
fi

# ------------------------------------------------------------------
# Extra: Fix ksud.h + ksud_integration.c — The SUSFS patch replaced the
# old ksu_execve_hook_ksud(pt_regs) API with ksu_handle_execveat_ksud(5 args).
# But syscall_event_bridge.c still calls the old API. We add compatibility
# wrapper functions in ksud_integration.c instead of modifying the header.
# ------------------------------------------------------------------
echo "[SUSFS-Fixup] Extra: Adding ksud compatibility wrappers..."
KSUD_H="$KSU_KERNEL/runtime/ksud.h"
KSUD_INT_C="$KSU_KERNEL/runtime/ksud_integration.c"

# Add old function declarations to ksud.h (AFTER the struct, before final #endif)
# We use a unique anchor to only match the file-level #endif
if [ -f "$KSUD_H" ] && ! grep -q "ksu_execve_hook_ksud" "$KSUD_H" 2>/dev/null; then
    # Use the ksu_handle_execveat_ksud declaration as anchor (it's after the struct)
    if grep -q "ksu_handle_execveat_ksud" "$KSUD_H" 2>/dev/null; then
        sed -i '/ksu_handle_execveat_ksud/,/;/{/;/a\
\
/* Compatibility wrappers for KernelSU-Next syscall_event_bridge.c */\
void ksu_execve_hook_ksud(const struct pt_regs *regs);\
void ksu_stop_input_hook_runtime(void);
}' "$KSUD_H"
    fi
fi

# Add compatibility wrapper functions in ksud_integration.c
if [ -f "$KSUD_INT_C" ] && ! grep -q "ksu_execve_hook_ksud" "$KSUD_INT_C" 2>/dev/null; then
    cat >> "$KSUD_INT_C" << 'KSUD_COMPAT_EOF'

/* =================================================================
 * Compatibility wrapper for KernelSU-Next's syscall_event_bridge.c
 * which calls ksu_execve_hook_ksud(regs) — the old pt_regs-based API.
 *
 * We CANNOT simply wrap the new ksu_handle_execveat_ksud() because:
 * 1) IS_ERR() on a stack-allocated struct filename returns true on ARM64
 *    (high kernel addresses look like error pointers), causing silent skip
 * 2) The SUSFS version sets ksu_execveat_hook=false, but KernelSU-Next
 *    uses static_branch_disable(&ksud_execve_key) for the hook gate
 *
 * Instead, we directly implement the init/zygote detection logic here,
 * matching what the original KernelSU-Next code did, plus SUSFS init.
 * ================================================================= */
extern void ksu_stop_ksud_execve_hook(void);

void ksu_execve_hook_ksud(const struct pt_regs *regs)
{
    const char __user **filename_user_p = (const char __user **)&PT_REGS_PARM1(regs);
    const char __user *const __user *__argv = (const char __user *const __user *)PT_REGS_PARM2(regs);
    struct user_arg_ptr argv = { .ptr.native = __argv };
    char path[256];
    long ret;
    unsigned long addr;
    const char __user *fn;

    static const char app_process[] = "/system/bin/app_process";
    static bool first_zygote = true;
    static const char system_bin_init[] = "/system/bin/init";
    static bool init_second_stage_executed = false;

    if (!filename_user_p)
        return;

    addr = untagged_addr((unsigned long)*filename_user_p);
    fn = (const char __user *)addr;

    memset(path, 0, sizeof(path));
    ret = strncpy_from_user(path, fn, sizeof(path) - 1);
    if (ret <= 0)
        return;

    /* Detect /system/bin/init second_stage — triggers SELinux rules + cred setup */
    if (unlikely(!memcmp(path, system_bin_init, sizeof(system_bin_init) - 1) && __argv)) {
        char buf[16];
        if (!init_second_stage_executed &&
            check_argv(argv, 1, "second_stage", buf, sizeof(buf))) {
            pr_info("/system/bin/init second_stage executed\n");
            apply_kernelsu_rules();
            cache_sid();
            setup_ksu_cred();
            init_second_stage_executed = true;
        }
    }

    /* Detect zygote exec — triggers on_post_fs_data (ksud setup, su binary) */
    if (unlikely(first_zygote && !memcmp(path, app_process, sizeof(app_process) - 1) && __argv)) {
        char buf[16];
        if (check_argv(argv, 1, "-Xzygote", buf, sizeof(buf))) {
            pr_info("exec zygote, /data prepared, second_stage: %d\n", init_second_stage_executed);
            on_post_fs_data();
            first_zygote = false;
            /* Use the KernelSU-Next mechanism to disable the hook */
            ksu_stop_ksud_execve_hook();
        }
    }

#ifdef CONFIG_KSU_SUSFS
    /* SUSFS process marking — call ksu_handle_execveat_init if available */
    {
        struct filename fname;
        fname.name = path;
        (void)ksu_handle_execveat_init(&fname, &argv, NULL);
    }
#endif
}

void ksu_stop_input_hook_runtime(void)
{
    extern bool ksu_input_hook;
    ksu_input_hook = false;
    pr_info("ksu_input_hook: %d\n", ksu_input_hook);
}
KSUD_COMPAT_EOF
fi

# Fix extern ksu_handle_execveat_init: replace with include
if [ -f "$KSUD_INT_C" ] && grep -q "extern int ksu_handle_execveat_init" "$KSUD_INT_C" 2>/dev/null; then
    # Include sucompat.h which has the declaration
    if ! grep -q "feature/sucompat.h" "$KSUD_INT_C" 2>/dev/null; then
        sed -i '/#include "selinux\/selinux.h"/a #include "feature/sucompat.h"' "$KSUD_INT_C"
    fi
    # Remove the extern declaration (we use the one from sucompat.h)
    sed -i '/^extern int ksu_handle_execveat_init/d' "$KSUD_INT_C"
fi

echo "[SUSFS-Fixup] All compatibility fixups applied successfully!"

