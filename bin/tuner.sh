#!/system/bin/sh

MODDIR=$(cd "${0%/*}" 2>/dev/null && cd .. && pwd)
[ -n "$MODDIR" ] || MODDIR=/data/adb/modules/KernelSU-Tuner

CFG_DIR=/data/adb/ksu_tuner
CFG=$CFG_DIR/config.conf
BAK=$CFG_DIR/backup.conf
LOG=$CFG_DIR/tuner.log
LOCK=$CFG_DIR/.lock
MAXLOG=300

mkdir -p "$CFG_DIR" 2>/dev/null
[ -f "$CFG" ] || : > "$CFG"
[ -f "$BAK" ] || : > "$BAK"

ts() {
  date '+%Y-%m-%d %H:%M:%S' 2>/dev/null
}

log() {
  printf '%s %s\n' "$(ts)" "$*" >> "$LOG" 2>/dev/null
  n=$(wc -l "$LOG" 2>/dev/null | awk '{print $1}')
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  if [ "$n" -gt "$MAXLOG" ]; then
    tail -n "$MAXLOG" "$LOG" > "$LOG.new" 2>/dev/null
    mv -f "$LOG.new" "$LOG" 2>/dev/null
  fi
}

cfg_get() {
  [ -f "$CFG" ] || return 1
  sed -n "s/^$1=//p" "$CFG" 2>/dev/null | tail -n 1
}

cfg_set() {
  sed -i "/^$1=/d" "$CFG" 2>/dev/null
  printf '%s=%s\n' "$1" "$2" >> "$CFG"
}

bk_save() {
  [ -e "$1" ] || return 0
  [ -f "$1" ] || return 0
  grep -qF "$1|" "$BAK" 2>/dev/null && return 0
  v=$(head -n 1 "$1" 2>/dev/null)
  [ -n "$v" ] || return 0
  printf '%s|%s\n' "$1" "$v" >> "$BAK"
}

wr() {
  [ -f "$1" ] || return 1
  bk_save "$1"
  chmod 0644 "$1" 2>/dev/null
  ( printf '%s' "$2" > "$1" ) 2>/dev/null || return 1
  return 0
}

acquire_lock() {
  i=0
  while [ "$i" -lt 12 ]; do
    mkdir "$LOCK" 2>/dev/null && return 0
    i=$((i + 1))
    sleep 1
  done
  return 0
}

release_lock() {
  rmdir "$LOCK" 2>/dev/null
  return 0
}

revert_all() {
  [ -s "$BAK" ] || return 0
  while IFS='|' read -r p v; do
    [ -n "$p" ] || continue
    [ -f "$p" ] || continue
    chmod 0644 "$p" 2>/dev/null
    ( printf '%s' "$v" > "$p" ) 2>/dev/null
  done < "$BAK"
  : > "$BAK"
  log "已回滚全部内核参数"
  printf '已回滚全部内核参数\n'
}

cpu_dirs() {
  found=0
  for d in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -d "$d" ] || continue
    printf '%s\n' "$d"
    found=1
  done
  [ "$found" = "1" ] && return 0
  for d in /sys/devices/system/cpu/cpu[0-9]*/cpufreq; do
    [ -d "$d" ] || continue
    printf '%s\n' "$d"
  done
}

first_cpu_dir() {
  cpu_dirs | head -n 1
}

pick_gov() {
  avail=$(cat "$1/scaling_available_governors" 2>/dev/null)
  [ -n "$avail" ] || return 1
  for g in $2; do
    case " $avail " in
      *" $g "*) printf '%s' "$g"; return 0 ;;
    esac
  done
  return 1
}

root_block() {
  for b in /sys/block/*; do
    [ -d "$b" ] || continue
    n=${b##*/}
    case "$n" in loop*|ram*|zram*|dm-*|sr*|fd*|md*) continue ;; esac
    [ -f "$b/queue/scheduler" ] || [ -f "$b/queue/read_ahead_kb" ] || continue
    printf '%s' "$n"
    return 0
  done
  return 1
}

apply_cpu() {
  prof=$1
  case "$prof" in
    powersave) glist="powersave schedutil ondemand conservative interactive" ;;
    balanced) glist="schedutil interactive ondemand conservative" ;;
    *) glist="performance schedutil interactive ondemand" ;;
  esac
  if [ "$(cfg_get CPU_GOV)" = "1" ]; then
    for d in $(cpu_dirs); do
      g=$(pick_gov "$d" "$glist")
      [ -n "$g" ] && wr "$d/scaling_governor" "$g"
    done
  fi
  if [ "$(cfg_get CPU_PIN)" = "1" ]; then
    for c in /sys/devices/system/cpu/cpu[0-9]*; do
      [ -f "$c/online" ] || continue
      wr "$c/online" 1
    done
  fi
}

apply_io() {
  prof=$1
  if [ "$(cfg_get IO_SCHED)" = "1" ]; then
    case "$prof" in
      powersave) slist="bfq mq-deadline kyber none deadline cfq" ;;
      balanced) slist="mq-deadline kyber bfq none deadline cfq" ;;
      *) slist="none mq-deadline kyber bfq deadline cfq" ;;
    esac
    for q in /sys/block/*/queue/scheduler; do
      [ -f "$q" ] || continue
      avail=$(cat "$q" 2>/dev/null)
      [ -n "$avail" ] || continue
      for s in $slist; do
        case "$avail" in
          *"[$s]"*) break ;;
          *"$s"*) wr "$q" "$s"; break ;;
        esac
      done
    done
  fi
  if [ "$(cfg_get READ_AHEAD)" = "1" ]; then
    ra=2048
    case "$prof" in
      powersave) ra=512 ;;
      balanced) ra=1024 ;;
      gaming) ra=4096 ;;
    esac
    for r in /sys/block/*/queue/read_ahead_kb; do
      wr "$r" "$ra"
    done
    for r in /sys/block/*/queue/nr_requests; do
      case "$prof" in
        powersave) wr "$r" 64 ;;
        balanced) wr "$r" 128 ;;
        *) wr "$r" 256 ;;
      esac
    done
  fi
}

apply_gpu() {
  [ "$(cfg_get GPU_TUNE)" = "1" ] || return 0
  prof=$1
  glvl=""
  case "$prof" in
    powersave) glvl="low" ;;
    balanced) glvl="mid" ;;
    performance) glvl="high" ;;
    gaming) glvl="max" ;;
  esac
  if [ -f /sys/class/kgsl/kgsl-3d0/max_pwrlevel ]; then
    n=$(cat /sys/class/kgsl/kgsl-3d0/num_pwrlevels 2>/dev/null)
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    if [ "$n" -gt 0 ]; then
      case "$glvl" in
        low) wr /sys/class/kgsl/kgsl-3d0/max_pwrlevel "$((n - 1))" ;;
        mid) wr /sys/class/kgsl/kgsl-3d0/max_pwrlevel "$((n / 2))" ;;
        *) wr /sys/class/kgsl/kgsl-3d0/max_pwrlevel 0 ;;
      esac
    fi
    wr /sys/class/kgsl/kgsl-3d0/idle_timer 80
    wr /sys/class/kgsl/kgsl-3d0/force_clk_on 0
  fi
  for d in /sys/class/devfreq/*gpu* /sys/class/devfreq/*.mali /sys/class/devfreq/*kgsl*; do
    [ -d "$d" ] || continue
    g=$(cat "$d/available_governors" 2>/dev/null)
    if [ -n "$g" ]; then
      case "$prof" in
        powersave)
          case " $g " in *" powersave "*) wr "$d/governor" powersave ;;
          *" simple_ondemand "*) wr "$d/governor" simple_ondemand ;;
          esac
          ;;
        *)
          case " $g " in
            *" performance "*) wr "$d/governor" performance ;;
            *" msm-adreno-tz "*) wr "$d/governor" msm-adreno-tz ;;
          esac
          ;;
      esac
    fi
  done
  if [ -d /sys/class/kgsl/kgsl-3d0/devfreq ]; then
    g=$(cat /sys/class/kgsl/kgsl-3d0/devfreq/available_governors 2>/dev/null)
    if [ -n "$g" ]; then
      case "$prof" in
        powersave)
          case " $g " in *" powersave "*) wr /sys/class/kgsl/kgsl-3d0/devfreq/governor powersave ;;
          *" simple_ondemand "*) wr /sys/class/kgsl/kgsl-3d0/devfreq/governor simple_ondemand ;;
          esac
          ;;
        *)
          case " $g " in
            *" performance "*) wr /sys/class/kgsl/kgsl-3d0/devfreq/governor performance ;;
            *" msm-adreno-tz "*) wr /sys/class/kgsl/kgsl-3d0/devfreq/governor msm-adreno-tz ;;
          esac
          ;;
      esac
    fi
  fi
}

apply_vm() {
  [ "$(cfg_get VM_TUNE)" = "1" ] || return 0
  prof=$1
  case "$prof" in
    powersave)
      wr /proc/sys/vm/swappiness 100
      wr /proc/sys/vm/vfs_cache_pressure 200
      wr /proc/sys/vm/dirty_ratio 20
      wr /proc/sys/vm/dirty_background_ratio 10
      wr /proc/sys/vm/dirty_expire_centisecs 3000
      wr /proc/sys/vm/dirty_writeback_centisecs 1500
      ;;
    balanced)
      wr /proc/sys/vm/swappiness 100
      wr /proc/sys/vm/vfs_cache_pressure 100
      wr /proc/sys/vm/dirty_ratio 20
      wr /proc/sys/vm/dirty_background_ratio 5
      wr /proc/sys/vm/dirty_expire_centisecs 3000
      wr /proc/sys/vm/dirty_writeback_centisecs 1500
      ;;
    *)
      wr /proc/sys/vm/swappiness 60
      wr /proc/sys/vm/vfs_cache_pressure 80
      wr /proc/sys/vm/dirty_ratio 15
      wr /proc/sys/vm/dirty_background_ratio 3
      wr /proc/sys/vm/dirty_expire_centisecs 1500
      wr /proc/sys/vm/dirty_writeback_centisecs 500
      ;;
  esac
  wr /proc/sys/vm/overcommit_memory 0
  wr /proc/sys/vm/stat_interval 1
}

apply_net() {
  [ "$(cfg_get NET_TUNE)" = "1" ] || return 0
  avail=$(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null)
  if [ -n "$avail" ]; then
    for c in bbr cubic westwood reno; do
      case " $avail " in
        *" $c "*) wr /proc/sys/net/ipv4/tcp_congestion_control "$c"; break ;;
      esac
    done
  fi
  wr /proc/sys/net/core/rmem_max 6291456
  wr /proc/sys/net/core/wmem_max 6291456
  wr /proc/sys/net/core/rmem_default 262144
  wr /proc/sys/net/core/wmem_default 262144
  wr /proc/sys/net/ipv4/tcp_fastopen 3
  wr /proc/sys/net/ipv4/tcp_tw_reuse 1
  wr /proc/sys/net/ipv4/tcp_fin_timeout 30
  wr /proc/sys/net/ipv4/tcp_syncookies 1
}

apply_zram() {
  [ "$(cfg_get ZRAM_TUNE)" = "1" ] || return 0
  swaps=$(cat /proc/swaps 2>/dev/null)
  for z in /sys/block/zram*; do
    [ -d "$z" ] || continue
    zn=${z##*/}
    case "$swaps" in *"$zn"*) continue ;; esac
    avail=$(cat "$z/comp_algorithm" 2>/dev/null)
    [ -n "$avail" ] || continue
    for a in zstd lz4 lzo lz4hc; do
      case "$avail" in
        *"[$a]"*) break ;;
        *"$a"*) wr "$z/comp_algorithm" "$a"; break ;;
      esac
    done
  done
}

apply_thermal() {
  if [ "$(cfg_get THERMAL_OPEN)" = "1" ]; then
    wr /sys/module/msm_thermal/parameters/enabled N
    wr /sys/module/msm_thermal/core_control/enabled N
    wr /sys/module/msm_thermal/vdd_restriction/enabled N
    for t in /sys/class/thermal/thermal_zone*/mode; do
      wr "$t" disabled
    done
  else
    for t in /sys/class/thermal/thermal_zone*/mode; do
      wr "$t" enabled
    done
  fi
}

apply_printk() {
  if [ "$(cfg_get PRINTK_OFF)" = "1" ]; then
    wr /proc/sys/kernel/printk "0 0 0 0"
    wr /proc/sys/kernel/printk_ratelimit 0
    wr /proc/sys/kernel/printk_devkmsg off
  fi
}

apply_selinux() {
  [ "$(cfg_get SELINUX_PERM)" = "1" ] || return 0
  if [ -x /system/bin/setenforce ]; then
    /system/bin/setenforce 0 2>/dev/null
  else
    setenforce 0 2>/dev/null
  fi
}

apply_ipv6() {
  if [ "$(cfg_get IPV6_OFF)" = "1" ]; then
    for d in /proc/sys/net/ipv6/conf/*/disable_ipv6; do
      wr "$d" 1
    done
  else
    for d in /proc/sys/net/ipv6/conf/*/disable_ipv6; do
      wr "$d" 0
    done
  fi
}

apply_dns() {
  [ "$(cfg_get DNS_TUNE)" = "1" ] || return 0
  prof=$1
  case "$prof" in
    powersave) d="114.114.114.114,223.5.5.5" ;;
    balanced) d="223.5.5.5,119.29.29.29" ;;
    *) d="1.1.1.1,8.8.8.8" ;;
  esac
  if command -v settings >/dev/null 2>&1; then
    settings put global private_dns_mode off 2>/dev/null
    settings put global private_dns_specifier "" 2>/dev/null
  fi
  for r in /system/etc/resolv.conf /etc/resolv.conf; do
    [ -d "$(dirname "$r")" ] || continue
    if [ -f "$r" ]; then
      wr "$r" "nameserver $(printf '%s' "$d" | cut -d, -f1)"
    fi
  done
  if [ "$prof" = "gaming" ] || [ "$prof" = "performance" ]; then
    if command -v settings >/dev/null 2>&1; then
      settings put global private_dns_mode hostname 2>/dev/null
      settings put global private_dns_specifier dns.google 2>/dev/null
    fi
  fi
}

do_apply() {
  prof=$1
  [ -n "$prof" ] || prof=$(cfg_get PROFILE)
  [ -n "$prof" ] || prof=balanced
  case "$prof" in
    powersave|balanced|performance|gaming) ;;
    *) prof=balanced ;;
  esac
  cfg_set PROFILE "$prof"
  acquire_lock
  apply_cpu "$prof"
  apply_gpu "$prof"
  apply_io "$prof"
  apply_vm "$prof"
  apply_net
  apply_dns "$prof"
  apply_zram
  apply_thermal
  apply_printk
  apply_selinux
  apply_ipv6
  release_lock
  if [ "$(cfg_get DISP_TUNE)" = "1" ] && [ -x "$MODDIR/bin/display.sh" ]; then
    sh "$MODDIR/bin/display.sh" apply "$prof" >/dev/null 2>&1
  fi
  if [ -s "$CFG_DIR/custom.conf" ] && [ -x "$MODDIR/bin/custom.sh" ]; then
    sh "$MODDIR/bin/custom.sh" apply >/dev/null 2>&1
  fi
  cfg_set LAST_APPLY "$(ts)"
  log "已应用预设: $prof"
  printf '已应用预设: %s\n' "$prof"
}

do_trim() {
  if command -v fstrim >/dev/null 2>&1; then
    out=$(fstrim -v /data 2>&1)
  else
    out=$(/system/bin/fstrim -v /data 2>&1)
  fi
  cfg_set LAST_TRIM "$(ts)"
  log "FSTRIM: $out"
  printf '%s\n' "$out"
}

do_status() {
  if [ -f "$CFG" ]; then
    while IFS='=' read -r k v; do
      [ -n "$k" ] || continue
      printf 'CFG_%s=%s\n' "$k" "$v"
    done < "$CFG"
  fi
  p=$(first_cpu_dir)
  if [ -n "$p" ]; then
    printf 'LIVE_GOVERNOR=%s\n' "$(cat "$p/scaling_governor" 2>/dev/null)"
    printf 'LIVE_GOV_AVAIL=%s\n' "$(cat "$p/scaling_available_governors" 2>/dev/null)"
    printf 'LIVE_CUR_FREQ=%s\n' "$(cat "$p/scaling_cur_freq" 2>/dev/null)"
    printf 'LIVE_MIN_FREQ=%s\n' "$(cat "$p/scaling_min_freq" 2>/dev/null)"
    printf 'LIVE_MAX_FREQ=%s\n' "$(cat "$p/scaling_max_freq" 2>/dev/null)"
  else
    printf 'LIVE_GOVERNOR=-\n'
    printf 'LIVE_GOV_AVAIL=-\n'
    printf 'LIVE_CUR_FREQ=-\n'
    printf 'LIVE_MIN_FREQ=-\n'
    printf 'LIVE_MAX_FREQ=-\n'
  fi
  blk=$(root_block)
  if [ -n "$blk" ]; then
    printf 'LIVE_BLOCK=%s\n' "$blk"
    printf 'LIVE_SCHEDULER=%s\n' "$(sed -n 's/.*\[\(.*\)\].*/\1/p' "/sys/block/$blk/queue/scheduler" 2>/dev/null | head -n 1)"
    printf 'LIVE_READAHEAD=%s\n' "$(cat "/sys/block/$blk/queue/read_ahead_kb" 2>/dev/null)"
  else
    printf 'LIVE_BLOCK=-\n'
    printf 'LIVE_SCHEDULER=-\n'
    printf 'LIVE_READAHEAD=-\n'
  fi
  printf 'LIVE_SWAPPINESS=%s\n' "$(cat /proc/sys/vm/swappiness 2>/dev/null)"
  printf 'LIVE_CONGESTION=%s\n' "$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)"
  printf 'LIVE_CONGESTION_AVAIL=%s\n' "$(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null)"
  if [ -x /system/bin/getenforce ]; then
    printf 'LIVE_SELINUX=%s\n' "$(/system/bin/getenforce 2>/dev/null)"
  else
    printf 'LIVE_SELINUX=%s\n' "$(getenforce 2>/dev/null)"
  fi
  printf 'LIVE_ZRAM_SIZE=%s\n' "$(cat /sys/block/zram0/disksize 2>/dev/null)"
  printf 'LIVE_ZRAM_ALGO=%s\n' "$(sed -n 's/.*\[\(.*\)\].*/\1/p' /sys/block/zram0/comp_algorithm 2>/dev/null | head -n 1)"
  printf 'LIVE_KERNEL=%s\n' "$(uname -r 2>/dev/null)"
  printf 'LIVE_KMI=%s\n' "$(getprop ro.bootimage.build.fingerprint 2>/dev/null)"
  printf 'LIVE_ANDROID=%s\n' "$(getprop ro.build.version.release 2>/dev/null)"
  printf 'LIVE_SDK=%s\n' "$(getprop ro.build.version.sdk 2>/dev/null)"
  printf 'LIVE_ABI=%s\n' "$(getprop ro.product.cpu.abi 2>/dev/null)"
  printf 'LIVE_MEMTOTAL=%s\n' "$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null)"
  printf 'LIVE_MEMAVAIL=%s\n' "$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null)"
  printf 'LIVE_UPTIME=%s\n' "$(cut -d' ' -f1 /proc/uptime 2>/dev/null)"
  printf 'LIVE_LOADAVG=%s\n' "$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)"
  printf 'LIVE_THERMAL=%s\n' "$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)"
  c=0
  for d in /sys/devices/system/cpu/cpu[0-9]*; do
    [ -d "$d" ] && c=$((c + 1))
  done
  printf 'LIVE_CORES=%s\n' "$c"
  if [ -f "$BAK" ]; then
    printf 'LIVE_BACKUPS=%s\n' "$(wc -l "$BAK" 2>/dev/null | awk '{print $1}')"
  else
    printf 'LIVE_BACKUPS=0\n'
  fi
  printf 'LIVE_LOG_LINES=%s\n' "$(wc -l "$LOG" 2>/dev/null | awk '{print $1}')"
  gclk=""
  for f in /sys/class/kgsl/kgsl-3d0/gpuclk /sys/class/kgsl/kgsl-3d0/devfreq/cur_freq /sys/class/devfreq/*gpu*/cur_freq; do
    [ -f "$f" ] || continue
    v=$(cat "$f" 2>/dev/null)
    case "$v" in ''|*[!0-9]*) continue ;; esac
    gclk=$((v / 1000000))
    break
  done
  [ -n "$gclk" ] || gclk="-"
  printf 'LIVE_GPUFREQ=%s\n' "$gclk"
  printf 'LIVE_GPUMODEL=%s\n' "$(cat /sys/class/kgsl/kgsl-3d0/gpu_model 2>/dev/null)"
  gmax=""
  for f in /sys/class/kgsl/kgsl-3d0/max_gpuclk /sys/class/kgsl/kgsl-3d0/devfreq/max_freq /sys/class/devfreq/*gpu*/max_freq; do
    [ -f "$f" ] || continue
    v=$(cat "$f" 2>/dev/null)
    case "$v" in ''|*[!0-9]*) continue ;; esac
    gmax=$((v / 1000000))
    break
  done
  [ -n "$gmax" ] || gmax="-"
  printf 'LIVE_GPUMAX=%s\n' "$gmax"
  cap=""
  for p in /sys/class/power_supply/battery/capacity /sys/class/power_supply/*/capacity; do
    [ -f "$p" ] || continue
    cap=$(cat "$p" 2>/dev/null)
    break
  done
  [ -n "$cap" ] || cap="-"
  printf 'LIVE_BATTERY=%s\n' "$cap"
  st=""
  for p in /sys/class/power_supply/*/status; do
    [ -f "$p" ] || continue
    st=$(cat "$p" 2>/dev/null)
    break
  done
  [ -n "$st" ] || st="-"
  printf 'LIVE_CHGSTATUS=%s\n' "$st"
  if [ -f "$CFG_DIR/autopilot.pid" ]; then
    ap=$(cat "$CFG_DIR/autopilot.pid" 2>/dev/null)
    if [ -n "$ap" ] && kill -0 "$ap" 2>/dev/null; then
      printf 'LIVE_AUTOPILOT=1\n'
    else
      printf 'LIVE_AUTOPILOT=0\n'
    fi
  else
    printf 'LIVE_AUTOPILOT=0\n'
  fi
  if [ -f "$CFG_DIR/guard.pid" ]; then
    gd=$(cat "$CFG_DIR/guard.pid" 2>/dev/null)
    if [ -n "$gd" ] && kill -0 "$gd" 2>/dev/null; then
      printf 'LIVE_GUARD=1\n'
    else
      printf 'LIVE_GUARD=0\n'
    fi
  else
    printf 'LIVE_GUARD=0\n'
  fi
  if [ -f "$CFG_DIR/autopilot.log" ]; then
    printf 'LIVE_APLOG=%s\n' "$(tail -n 1 "$CFG_DIR/autopilot.log" 2>/dev/null)"
  else
    printf 'LIVE_APLOG=-\n'
  fi
  printf 'LIVE_GPULEVEL=%s\n' "$(cat /sys/class/kgsl/kgsl-3d0/max_pwrlevel 2>/dev/null)"
  if [ -x "$MODDIR/bin/display.sh" ]; then
    d=$(sh "$MODDIR/bin/display.sh" status 2>/dev/null)
    printf '%s\n' "$d"
  fi
  if [ -f "$CFG_DIR/appwatch.pid" ]; then
    aw=$(cat "$CFG_DIR/appwatch.pid" 2>/dev/null)
    if [ -n "$aw" ] && kill -0 "$aw" 2>/dev/null; then
      printf 'LIVE_APPWATCH=1\n'
    else
      printf 'LIVE_APPWATCH=0\n'
    fi
  else
    printf 'LIVE_APPWATCH=0\n'
  fi
  printf 'LIVE_RULECOUNT=%s\n' "$(wc -l "$CFG_DIR/apprules.conf" 2>/dev/null | awk '{print $1}')"
  printf 'LIVE_CUSTOMCOUNT=%s\n' "$(wc -l "$CFG_DIR/custom.conf" 2>/dev/null | awk '{print $1}')"
  if [ -f "$MODDIR/initrc/KernelSU-Tuner.rc" ]; then
    printf 'LIVE_INITRC=1\n'
  else
    printf 'LIVE_INITRC=0\n'
  fi
  printf 'LIVE_FOREGROUND=%s\n' "$(sh "$MODDIR/bin/appwatch.sh" fg 2>/dev/null)"
}

do_monitor() {
  n=0
  while [ "$n" -lt 3 ]; do
    t=0
    for z in /sys/class/thermal/thermal_zone*; do
      [ -d "$z" ] || continue
      v=$(cat "$z/temp" 2>/dev/null)
      case "$v" in ''|*[!0-9]*) continue ;; esac
      [ "$v" -gt "$t" ] && t=$v
    done
    case "$t" in ''|*[!0-9]*) t=0 ;; esac
    if [ "$t" -gt 0 ] && [ "$t" -lt 200 ]; then t=$((t * 1000)); fi
    tc=$((t / 1000))

    cpu=0
    for s in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do
      v=$(cat "$s" 2>/dev/null)
      case "$v" in ''|*[!0-9]*) continue ;; esac
      [ "$v" -gt "$cpu" ] && cpu=$v
    done
    cpu=$((cpu / 1000))

    freq=""
    for d in /sys/devices/system/cpu/cpufreq/policy*; do
      [ -d "$d" ] || continue
      c=$(cat "$d/scaling_cur_freq" 2>/dev/null)
      case "$c" in ''|*[!0-9]*) c=0 ;; esac
      [ -n "$freq" ] && freq="$freq,"
      freq="$freq$((c / 1000))"
    done

    g=0
    for f in /sys/class/kgsl/kgsl-3d0/gpuclk /sys/class/kgsl/kgsl-3d0/devfreq/cur_freq /sys/class/devfreq/*gpu*/cur_freq; do
      [ -f "$f" ] || continue
      v=$(cat "$f" 2>/dev/null)
      case "$v" in ''|*[!0-9]*) continue ;; esac
      [ "$v" -gt "$g" ] && g=$v
    done
    g=$((g / 1000000))

    load=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null)
    bat=""
    for p in /sys/class/power_supply/*/capacity; do
      [ -f "$p" ] || continue
      bat=$(cat "$p" 2>/dev/null)
      break
    done
    cur=""
    for p in /sys/class/power_supply/*/current_now; do
      [ -f "$p" ] || continue
      cur=$(cat "$p" 2>/dev/null)
      break
    done
    mem=$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null)

    printf 'TEMP=%s\n' "$tc"
    printf 'CPUFREQ=%s\n' "$cpu"
    printf 'CORES=%s\n' "$freq"
    printf 'GPUFREQ=%s\n' "$g"
    printf 'LOAD=%s\n' "$load"
    printf 'BATT=%s\n' "$bat"
    printf 'CURR=%s\n' "$cur"
    printf 'MEMAVAIL=%s\n' "$mem"
    printf '%s\n' '---'

    n=$((n + 1))
    [ "$n" -lt 3 ] && sleep 1
  done
}

apply_fast() {
  prof=$1
  case "$prof" in
    powersave|balanced|performance|gaming) ;;
    *) prof=$(cfg_get PROFILE) ;;
  esac
  [ -n "$prof" ] || prof=balanced
  acquire_lock
  apply_cpu "$prof"
  apply_gpu "$prof"
  apply_vm "$prof"
  apply_thermal
  release_lock
  if [ "$(cfg_get DISP_TUNE)" = "1" ] && [ -x "$MODDIR/bin/display.sh" ]; then
    sh "$MODDIR/bin/display.sh" apply "$prof" >/dev/null 2>&1
  fi
  cfg_set PROFILE "$prof"
  cfg_set LAST_APPLY "$(ts)"
  log "快速切换: $prof"
  printf '已快速切换: %s\n' "$prof"
}

cmd=$1
shift 2>/dev/null

case "$cmd" in
  apply)
    do_apply "$1"
    ;;
  fast)
    apply_fast "$1"
    ;;
  monitor)
    do_monitor
    ;;
  revert)
    revert_all
    cfg_set LAST_APPLY "-"
    ;;
  status)
    do_status
    ;;
  set)
    if [ -n "$1" ]; then
      cfg_set "$1" "$2"
      printf 'OK %s=%s\n' "$1" "$2"
    fi
    ;;
  get)
    cfg_get "$1"
    printf '\n'
    ;;
  list)
    cat "$CFG" 2>/dev/null
    ;;
  trim)
    do_trim
    ;;
  log)
    tail -n 120 "$LOG" 2>/dev/null
    ;;
  clear-log)
    : > "$LOG"
    printf 'OK\n'
    ;;
  reset)
    : > "$BAK"
    do_apply "$1"
    ;;
  *)
    printf 'usage: tuner.sh {apply [profile]|fast [profile]|monitor|revert|status|set K V|get K|list|trim|log|clear-log|reset [profile]}\n'
    ;;
esac

release_lock