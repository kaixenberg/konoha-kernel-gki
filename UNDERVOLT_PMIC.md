# PMIC Undervolting Log

| Regulator Name | Default Min Voltage | Tested Undervolt | Status | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `display_panel_vddldo` (reg.76)| 1.2V (1200000) | 1.10V (1100000) | Ignored| Fixed regulator (GPIO switch), hardware incapable of variable voltage. |
| `pm_v6g_l2` (regulator.57)   | 1.20V (1200000) | 0.20V (200000)  | Stable | Massive -1.0V drop |
| `pm_v6g_l3` (regulator.58)   | 1.80V (1800000) | 0.05V (50000)   | Testing| Attempting even lower undervolt to 0.05V. |
| `pm_v6g_l3` (regulator.58)   | 1.80V (1800000) | 1.00V (1000000) | Stable | Massive -0.8V drop |
| `pm_v6g_s1` (regulator.55)   | 2.15V (2156000) | 0.10V (100000)  | Stable | Massive -2.05V drop (Buck/SMPS) |
| `pm_v6g_s1` (regulator.55)   | 2.15V (2156000) | 0.50V (500000)  | Stable | Massive -1.65V drop (Buck/SMPS) |
| `pm_v6g_s1` (regulator.55)   | 2.15V (2156000) | 1.00V (1000000) | Stable | Massive -1.15V drop (Buck/SMPS) |
| `pm_v6g_s1` (regulator.55)   | 2.15V (2156000) | 1.50V (1500000) | Stable | Massive -0.65V drop (Buck/SMPS) |
| `pm_v8f_s1_level` (reg.41)   | 256 (NOM)       | 128 (SVS)       | Stable | Safe hardware floor. |
| `pm_v8f_s1_level` (reg.41)   | 256 (NOM)       | 16 (RETENTION)  | Failed | Caused msm_vidc (Venus Codec) hardware hang. Reverted to 128. |
| `pm_v8f_s1_level` (reg.41)   | 256 (NOM)       | 64 (LOW_SVS)    | Failed | Caused white screen / display corruption. |
| `pm_v8f_s2_level` (reg.29)   | 256 (NOM)       | 128 (SVS)       | Stable | Safe hardware floor. |
| `pm_v8f_s2_level` (reg.29)   | 256 (NOM)       | 56              | Failed | Caused Venus Codec crash. Reverted. |
| `pm_v8f_s2_level` (reg.29)   | 256 (NOM)       | 64 (LOW_SVS)    | Failed | Caused white screen / display corruption. |
| `pm_v8f_s2_level` (reg.29)   | 56 (Default)    | 32 (RET_LOW)    | Failed | Caused black screen / display logic failure. |
| `pm_v8f_s2_level` (reg.29)   | 56 (Default)    | 48 (MIN_SVS)    | Failed | Caused black screen. Removed from overrides (defaults to native 56). |
| `pm_v8f_s8_level` (reg.43)   | 256 (NOM)       | 128 (SVS)       | Stable | Safe hardware floor. |
| `pm_v8f_s8_level` (reg.43)   | 256 (NOM)       | 16 (RETENTION)  | Failed | Video Clock Controller starved, causing Venus crash. Reverted. |
| `pm_v8f_s8_level` (reg.43)   | 256 (NOM)       | 32 (RET_LOW)    | Failed | Caused black screen (Video/Display Clock starvation). |
| `pm_v8f_s8_level` (reg.43)   | 256 (NOM)       | 56              | Testing| Pushing undervolt further for clock controllers. |
| `pm_v8f_s8_level` (reg.43)   | 256 (NOM)       | 64 (LOW_SVS)    | Failed | Caused white screen / display corruption. |
| `pm_v8f_s8_level` (reg.43)   | 256 (NOM)       | 64 (LOW_SVS)    | Stable | Safe clock controller floor. |
| `pmxr2230_l12` (regulator.14)| 2.40V (2400000) | 0.30V (300000)  | Stable | Massive -2.1V drop |
| `pmxr2230_l16` (regulator.17)| 3.3V (3300000) | 0.50V (500000)  | Stable | Massive -2.8V drop |
| `pmxr2230_l16` (regulator.17)| 3.3V (3300000) | 1.50V (1500000) | Stable | Massive -1.8V drop |
| `pmxr2230_l16` (regulator.17)| 3.3V (3300000) | 2.50V (2500000) | Stable | Massive -0.8V drop |
| `pmxr2230_l16` (regulator.17)| 3.3V (3300000) | 3.00V (3000000) | Stable | - |
| `pmxr2230_l17` (regulator.18)| 2.70V (2700000) | 0.20V (200000)  | Stable | Massive -2.5V drop |
| `pmxr2230_l17` (regulator.18)| 2.70V (2700000) | 1.00V (1000000) | Stable | Massive -1.7V drop |
| `pmxr2230_l17` (regulator.18)| 2.70V (2700000) | 2.00V (2000000) | Stable | Massive -0.7V drop |
| `pmxr2230_l18` (regulator.19)| 1.60V (1600000) | 1.00V (1000000) | Stable | Massive -0.6V drop |
| `pmxr2230_l19` (regulator.20)| 2.65V (2650000) | 0.30V (300000)  | Stable | Massive -2.35V drop |
| `pmxr2230_l19` (regulator.20)| 2.65V (2650000) | 1.50V (1500000) | Stable | Massive -1.15V drop |
| `pmxr2230_l19` (regulator.20)| 2.65V (2650000) | 2.50V (2500000) | Stable | -0.15V drop |
| `pmxr2230_l4` (regulator.7)  | 1.20V (1200000) | 0.20V (200000)  | Stable | Massive -1.0V drop |
| `pmxr2230_l4` (regulator.7)  | 1.20V (1200000) | 0.30V (300000)  | Stable | Massive -0.9V drop |
| `pmxr2230_l7` (regulator.9)  | 1.80V (1800000) | 0.80V (800000)  | Stable | Massive -1.0V drop |
| `pmxr2230_l8` (regulator.10) | 1.8V (1800000) | 0.03V (30000)  | Testing| Attempting extreme undervolt to 0.03V. |
| `pmxr2230_l8` (regulator.10) | 1.8V (1800000) | 0.80V (800000) | Stable | - |
| `pmxr2230_l8` (regulator.10) | 1.8V (1800000) | 1.10V (1100000) | Stable | - |
| `pmxr2230_l8` (regulator.10) | 1.8V (1800000) | 1.40V (1400000) | Stable | - |
| `pmxr2230_l8` (regulator.10) | 1.8V (1800000) | 1.65V (1650000) | Stable | - |
| `pmxr2230_l8` (regulator.10) | 1.8V (1800000) | 1.70V (1700000) | Stable | - |
| `pmxr2230_s1` (regulator.1)  | 1.84V (1840000) | 0.50V (500000)  | Stable | Massive -1.34V drop (Buck/SMPS) |
| `pmxr2230_s2` (regulator.2)  | 1.24V (1240000) | 0.30V (300000)  | Stable | Massive -0.94V drop (Buck/SMPS) |
| `pmxr2230_s3` (regulator.3)  | 0.86V (864000)  | 0.08V (80000)   | Testing| Attempting even lower undervolt to 0.08V. |
