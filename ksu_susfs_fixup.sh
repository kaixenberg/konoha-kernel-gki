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
# 7. hook/setuid_hook.c: Add do_umount label + tp_marker.h include
# ------------------------------------------------------------------
echo "[SUSFS-Fixup] 7/8 hook/setuid_hook.c: Adding do_umount label + tp_marker.h..."
SETUID_HOOK_C="$KSU_KERNEL/hook/setuid_hook.c"

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
 * Compatibility wrappers for KernelSU-Next's syscall_event_bridge.c
 * which still calls the old API. These translate old->new signatures.
 * ================================================================= */
void ksu_execve_hook_ksud(const struct pt_regs *regs)
{
    if (!regs)
        return;

    const char __user *filename_user = (const char __user *)PT_REGS_PARM1(regs);
    const char __user *const __user *__argv = (const char __user *const __user *)PT_REGS_PARM2(regs);
    struct user_arg_ptr argv = { .ptr.native = __argv };
    char path[32];

    memset(path, 0, sizeof(path));
    if (strncpy_from_user(path, filename_user, sizeof(path)) <= 0)
        return;

    // Call the new SUSFS-compatible function with adapted parameters
    struct filename fname;
    fname.name = path;
    struct filename *fname_ptr = &fname;
    ksu_handle_execveat_ksud(NULL, &fname_ptr, &argv, NULL, NULL);
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

