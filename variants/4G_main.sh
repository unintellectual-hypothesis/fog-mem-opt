#!/system/bin/sh
# Constructed by: free @ Telegram // unintellectual-hypothesis @GitHub
MODDIR=${0%/*}

# Set Original Module Directory
MODULE_PATH="$(dirname $(readlink -f "$0"))"
MODULE_PATH="${MODULE_PATH%/variants}"

# load libraries
MEM_FEATURES_DIR="$MODULE_PATH/mem-features"
. "$MEM_FEATURES_DIR"/tools.sh
. "$MEM_FEATURES_DIR"/intelligent_zram_writeback.sh

high_load_threshold=""
medium_load_threshold=""
WRITEBACK_NUM=0
apps=""
app_switch=0
app_switch_threshold=""
enable_hybrid_swap=""
zram_disksize=""
zram_algo=""


start_dynamic_swappiness()
{
  # Default threshold values
  high_load_threshold="$(read_cfg high_load_threshold)"
  [ "$high_load_threshold" == "" ] && high_load_threshold=50
  medium_load_threshold="$(read_cfg medium_load_threshold)"
  [ "$medium_load_threshold" == "" ] && medium_load_threshold=25
  while true; do
  load_avg=$(awk  '{printf "%.0f", ($1 * 100 / 8)}'  /proc/loadavg)
    if [ "$load_avg" -ge "$(read_cfg high_load_threshold)" ]; then
      resetprop -n ro.lmk.use_minfree_levels false
      if [ "$swap_over_hundy" -eq 1 ]; then
        set_val "100" $VM/swappiness
        set_val "200" $VM/vfs_cache_pressure
      elif [ "$swap_over_hundy" -eq 0 ]; then
        set_val "85" $VM/swappiness
        set_val "200" $VM/vfs_cache_pressure
      fi
    elif [ "$load_avg" -ge "$(read_cfg medium_load_threshold)" ]; then
      resetprop -n ro.lmk.use_minfree_levels true
      if [ "$swap_over_hundy" -eq 1 ]; then
        set_val "165" $VM/swappiness
        set_val "140" $VM/vfs_cache_pressure
      elif [ "$swap_over_hundy" -eq 0 ]; then
        set_val "90" $VM/swappiness
        set_val "140" $VM/vfs_cache_pressure
      fi
    elif [ "$load_avg" -ge 0 ]; then
      resetprop -n ro.lmk.use_minfree_levels true
      if [ "$swap_over_hundy" -eq 1 ]; then
        set_val "180" $VM/swappiness
        set_val "110" $VM/vfs_cache_pressure
      elif [ "$swap_over_hundy" -eq 0 ]; then
        set_val "100" $VM/swappiness
        set_val "110" $VM/vfs_cache_pressure
      fi
    fi
    sleep 5
  done &
}

swapfile_status()
{
    local swap_info
    swap_info="$(cat /proc/swaps | grep "$SWAP_DIR"/swapfile)"
    if [ "$swap_info" != "" ] && [ "$(read_cfg zram_disksize)" -eq 0 ]; then
        echo "Hybrid Swap Enabled. Size $(echo "$swap_info" | awk '{print $3}')kB."
    elif [ "$swap_info" != "" ]; then
        echo "Swapfile Enabled, ZRAM Disabled. Size $(echo "$swap_info" | awk '{print $3}')kB. Disabled Qualcomm's PPR"
    else
        echo "Disabled by user."
    fi
}

conf_hybrid_swap()
{
    enable_hybrid_swap="$(read_cfg enable_hybrid_swap)"
    [ "$enable_hybrid_swap" == "" ] && enable_hybrid_swap=0

    if [ "$(read_cfg enable_hybrid_swap)" -eq 1 ]; then
        if [ -f "$SWAP_DIR"/swapfile ]; then
            toybox swapon -d "$SWAP_DIR"/swapfile -p 1111
        else
            mkdir "$SWAP_DIR"
            dd if=/dev/zero of="$SWAP_DIR"/swapfile bs=1M count=32
            toybox mkswap "$SWAP_DIR"/swapfile
            toybox swapon -d "$SWAP_DIR"/swapfile -p 1111
        fi

        # Enable Qualcomm's Per-Process Reclaim for Hybrid Swap Setup IF AND ONLY IF, ZRAM and Swapfile are on at the same time
        if [ "$(read_cfg zram_disksize)" != "0" ]; then
            set_val "1" /sys/module/process_reclaim/parameters/enable_process_reclaim
            set_val "90" /sys/module/process_reclaim/parameters/pressure_max
            set_val "70" /sys/module/process_reclaim/parameters/pressure_min
            set_val "256" /sys/module/process_reclaim/parameters/per_swap_size
        fi
    fi
}

# Test if kernel supports swappiness over 100 (Some ROM defaults swappiness to 100)
test_swappiness()
{
  set_val "160" $VM/swappiness
  new_swappiness=$(cat $VM/swappiness)
  if [ "$new_swappiness" -eq 160 ]; then
    swap_over_hundy=1
  else
    swap_over_hundy=0
  fi
}

conf_vm_param()
{
    set_val "10" "$VM"/dirty_ratio
    set_val "3" "$VM"/dirty_background_ratio
    set_val "76800" "$VM"/extra_free_kbytes
    set_val "8192" "$VM"/min_free_kbytes
    set_val "3000" "$VM"/dirty_expire_centisecs
    set_val "4000" "$VM"/dirty_writeback_centisecs
    
    # Don't need to set watermark_scale_factor since we already have vm.extra_free_kbytes. See /proc/zoneinfo for more info
    set_val "1" "$VM"/watermark_scale_factor

    # Use multiple threads to run kswapd for better swapping performance
    set_val "8" "$VM"/kswapd_threads
}

conf_zram_param()
{
    # load size from file
    zram_disksize="$(read_cfg zram_disksize)"
    case "$zram_disksize" in
        0|0.5|1|1.5|2|2.5|3|4|5|6|8) ;;
        *) zram_disksize=2.5 ;;
    esac

    # load algorithm from file, use lz0 as default
    zram_algo="$(read_cfg zram_algo)"
    [ "$zram_algo" == "" ] && zram_algo="lz0"

    # ~2.8x compression ratio
    # higher disksize result in larger space-inefficient SwapCache
    case "$zram_disksize" in
        0)  swap_all_off ;;
        0.5)  zram_on 512M 160M "$zram_algo" ;;
        1)  zram_on 1024M 360M "$zram_algo" ;;
        1.5)  zram_on 1536M 540M "$zram_algo" ;;
        2)  zram_on 2048M 720M "$zram_algo" ;;
        2.5)  zram_on 2560M 900M "$zram_algo" ;;
        3)  zram_on 3072M 1080M "$zram_algo" ;;
        4)  zram_on 4096M 1440M "$zram_algo" ;;
        5)  zram_on 5120M 1800M "$zram_algo" ;;
        6)  zram_on 6144M 2160M "$zram_algo" ;;
        8)  zram_on 8192M 2880M "$zram_algo" ;;
    esac
}

write_conf_file()
{
    clear_cfg
    write_cfg "Welcome Back"
    write_cfg ""
    write_cfg "Redmi 10C RAM Management"
    write_cfg "——————————————————"
    write_cfg "Huge Credits to: @yc9559, @helloklf @VR-25, @pedrozzz0, @agnostic-apollo, and other developers"
    write_cfg "Module constructed by free @ Telegram // unintellectual-hypothesis @ GitHub"
    write_cfg "Last time module executed: $(date '+%Y-%m-%d %H:%M:%S')"
    write_cfg "Version: v1.0"
    write_cfg ""
    write_cfg "[ZRAM status]"
    write_cfg "$(zram_status)"
    write_cfg ""
    write_cfg "[FSCC status]"
    write_cfg "$(fscc_status)"
    write_cfg ""
    write_cfg "[Swapfile status]"
    write_cfg "$(swapfile_status)"
    write_cfg ""
    write_cfg "[Settings]"
    write_cfg "# ZRAM Available size (GB): 0 / 0.5 / 1 / 1.5 / 2 / 2.5 / 3 / 4 / 5 / 6 / 8"
    write_cfg "zram_disksize=$zram_disksize"
    write_cfg "# Available compression algorithm: $(zram_avail_comp_alg)"
    write_cfg "zram_algo=$zram_algo"
    write_cfg ""
    write_cfg "# Hybrid Swap (System will use swapfile when ZRAM is exhausted). Enter 0 to disable hybrid swap or enter 1 to enable hybrid swap"
    write_cfg "enable_hybrid_swap=$enable_hybrid_swap"
    write_cfg ""
    if [ "$(zram_wb_support)" -eq 1 ] && [ "$(cat $ZRAM_SYS/backing_dev)" != "none" ]; then
        write_cfg "# ZRAM Writeback, set the minimum number of app switch before performing small ZRAM Writeback "
        write_cfg "app_switch_threshold=$app_switch_threshold"
        write_cfg ""
    fi
    write_cfg "# Dynamic Swappiness: High Load Threshold. Default value is 50 (Recommended value between 50 ~ 75)"
    write_cfg "high_load_threshold=$high_load_threshold"
    write_cfg ""
    write_cfg "# Dynamic Swappiness: Medium Load Threshold. Default value is 25 (Recommended value between 25 ~ 50)"
    write_cfg "medium_load_threshold=$medium_load_threshold"
}

# Wait until boot finish
resetprop -w sys.boot_completed 0
sleep 2

# Disable again, because some ROMS activate ZRAM after boot
swap_all_off
zram_reset

wait_until_unlock
conf_zram_param

# Start the rest of the script a little late to run the system first
sleep 10
conf_vm_param
test_swappiness

# Dynamic swappiness & vfs_cache_pressure based on /proc/loadavg
start_dynamic_swappiness

start_auto_zram_writeback
conf_hybrid_swap

change_task_affinity "kswapd"
change_task_affinity "oom_reaper"
change_task_nice "kswapd"
change_task_nice "oom_reaper"

# Start FSCC
"$MODULE_PATH"/system/bin/fscc

# LMKD Minfree Levels, Thanks to helloklf @ GitHub
if [ "$MEM_TOTAL" -le 3145728 ]; then
  resetprop -n sys.lmk.minfree_levels 4096:0,5120:100,8192:200,16384:250,24576:900,39936:950
elif [ "$MEM_TOTAL" -le 4194304 ]; then
  resetprop -n sys.lmk.minfree_levels 4096:0,5120:100,8192:200,24576:250,32768:900,47360:950
elif [ "$MEM_TOTAL" -gt 4194304 ]; then
  resetprop -n sys.lmk.minfree_levels 4096:0,5120:100,8192:200,32768:250,56320:900,71680:950
fi

write_conf_file

exit 0
