#!/system/bin/sh
MODDIR=${0%/*}

# Userspace LMKD Optimization
resetprop -n ro.lmk.use_new_strategy 1
resetprop -n ro.lmk.thrashing_min_score_adj 0
resetprop -n ro.lmk.low 1001
resetprop -n ro.lmk.medium 907
resetprop -n ro.lmk.critical 800
resetprop -n ro.lmk.swap_free_low_percentage 5
resetprop -n ro.lmk.enhance_batch_kill false
resetprop -n ro.lmk.enable_adaptive_lmk false
resetprop -n ro.lmk.use_minfree_levels false
resetprop -n ro.lmk.critical_upgrade true
resetprop -n ro.lmk.upgrade_pressure 100
resetprop -n ro.lmk.downgrade_pressure 100
resetprop -n ro.lmk.kill_heaviest_task false
resetprop -n ro.lmk.kill_timeout_ms 30
resetprop -n ro.lmk.use_psi true
resetprop -n ro.lmk.psi_partial_stall_ms 750
resetprop -n ro.lmk.psi_complete_stall_ms 1600
resetprop -n ro.lmk.swap_util_max 100
resetprop -n ro.lmk.thrashing_limit 30
resetprop -n ro.lmk.thrashing_limit_decay 50
resetprop -p --delete persist.device_config.lmkd_native.thrashing_limit_critical
resetprop -p --delete lmkd.reinit
