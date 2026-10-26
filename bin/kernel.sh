#!/system/bin/sh

CFG_DIR=/data/adb/ksu_tuner
CFG=$CFG_DIR/config.conf
BAK=$CFG_DIR/backup.conf
SYS=${KSU_SYS:-}

mkdir -p "$CFG_DIR" 2>/dev/null
[ -f "$CFG" ] || : > "$CFG"
[ -f "$BAK" ] || : > "$BAK"

cfg_read() {
  [ -f "$CFG" ] || return 1
  sed -n "s/^$1=//p" "$CFG" 2>/dev/null | tail -n 1
}

read1() {
  head -n 1 "$1" 2>/dev/null | tr -d '\n\r'
}

is_num() {
  case "$1" in
    ''|*[!0-9-]*) return 1 ;;
    -) return 1 ;;
    --*|-*-*) return 1 ;;
  esac
  return 0
}

bk_save() {
  [ -f "$1" ] || return 0
  grep -qF "$1|" "$BAK" 2>/dev/null && return 0
  v=$(read1 "$1")
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

wrs() {
  [ -f "$1" ] || return 1
  [ -n "$2" ] || return 1
  cur=$(read1 "$1")
  [ "$cur" = "$2" ] && return 0
  wr "$1" "$2"
}

mem_mb() {
  k=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null)
  is_num "$k" || k=0
  [ "$k" -gt 0 ] || k=$(awk '/MemTotal/ {print $2}' "$SYS/proc/meminfo" 2>/dev/null)
  is_num "$k" || k=0
  printf '%s' "$((k / 1024))"
}

profile_of() {
  p=$1
  [ -n "$p" ] || p=$(cfg_read PROFILE)
  [ -n "$p" ] || p=balanced
  case "$p" in
    powersave|balanced|performance|gaming) ;;
    *) p=balanced ;;
  esac
  printf '%s' "$p"
}

devfreq_dirs() {
  for d in "$SYS/sys/class/devfreq"/*; do
    [ -d "$d" ] || continue
    [ -f "$d/governor" ] || continue
    printf '%s\n' "$d"
  done
}

devfreq_gov() {
  p=$(profile_of "$1")
  case "$p" in
    powersave) printf 'powersave' ;;
    balanced) printf 'simple_ondemand' ;;
    performance) printf 'performance' ;;
    gaming) printf 'performance' ;;
  esac
}

apply_devfreq() {
  p=$(profile_of "$1")
  n=0
  s=0
  for d in $(devfreq_dirs); do
    av=$(read1 "$d/available_governors")
    [ -n "$av" ] || av=$(read1 "$d/governor")
    want=$(devfreq_gov "$p")
    hit=0
    for g in $av; do
      [ "$g" = "$want" ] && hit=1
    done
    [ "$hit" = "1" ] || want=$(read1 "$d/governor")
    if wrs "$d/governor" "$want"; then
      n=$((n + 1))
    else
      s=$((s + 1))
    fi
    case "$p" in
      powersave)
        lo=$(read1 "$d/min_freq")
        [ -n "$lo" ] && wrs "$d/min_freq" "$lo" >/dev/null 2>&1
        hi=$(read1 "$d/available_frequencies" | tr ' ' '\n' | sed -n '2p')
        [ -n "$hi" ] && wrs "$d/max_freq" "$hi" >/dev/null 2>&1
        ;;
      gaming)
        hi=$(read1 "$d/available_frequencies" | tr ' ' '\n' | tail -n 1)
        [ -n "$hi" ] && wrs "$d/max_freq" "$hi" >/dev/null 2>&1
        ;;
    esac
  done
  printf 'devfreq 已调 %s 项，跳过 %s 项\n' "$n" "$s"
}

list_devfreq() {
  for d in $(devfreq_dirs); do
    printf '%s\n' "$d"
    printf '  governor  = %s\n' "$(read1 "$d/governor")"
    printf '  available = %s\n' "$(read1 "$d/available_governors")"
    printf '  cur_freq  = %s\n' "$(read1 "$d/cur_freq")"
    printf '  min/max   = %s / %s\n' "$(read1 "$d/min_freq")" "$(read1 "$d/max_freq")"
  done
}

apply_ksm() {
  on=$(cfg_read KSM)
  [ "$on" = "1" ] || { printf 'KSM 未开启，跳过\n'; return 0; }
  n=0
  for b in "$SYS/sys/kernel/mm/ksm" "$SYS/sys/kernel/mm/ksm_ksm"; do
    [ -d "$b" ] || continue
    wrs "$b/run" "1" >/dev/null 2>&1 && n=$((n + 1))
    wrs "$b/pages_to_scan" "256" >/dev/null 2>&1
    wrs "$b/sleep_millisecs" "1000" >/dev/null 2>&1
    wrs "$b/merge_across_nodes" "1" >/dev/null 2>&1
  done
  printf 'KSM 已启用 %s 处\n' "$n"
}

apply_thp() {
  on=$(cfg_read THP)
  [ "$on" = "1" ] || { printf 'THP 未开启，跳过\n'; return 0; }
  p=$(profile_of "$1")
  case "$p" in
    powersave) want="madvise" ;;
    balanced) want="madvise" ;;
    performance) want="always" ;;
    gaming) want="always" ;;
  esac
  n=0
  for f in "$SYS/sys/kernel/mm/transparent_hugepage/enabled" "$SYS/sys/kernel/mm/transparent_hugepage/defrag"; do
    [ -f "$f" ] || continue
    wrs "$f" "$want" >/dev/null 2>&1 && n=$((n + 1))
  done
  for f in "$SYS/sys/kernel/mm/transparent_hugepage/khugepaged/defrag"; do
    [ -f "$f" ] || continue
    case "$p" in
      powersave) wrs "$f" "0" >/dev/null 2>&1 ;;
      *) wrs "$f" "1" >/dev/null 2>&1 ;;
    esac
  done
  pc="$SYS/proc/sys/vm/page-cluster"
  if [ -f "$pc" ]; then
    case "$p" in
      powersave) wrs "$pc" "0" >/dev/null 2>&1 ;;
      gaming) wrs "$pc" "3" >/dev/null 2>&1 ;;
      *) wrs "$pc" "1" >/dev/null 2>&1 ;;
    esac
  fi
  printf 'THP 已设 %s (%s 处)\n' "$want" "$n"
}

stune_dir() {
  for d in "$SYS/dev/stune" "$SYS/dev/stune_ksu" "$SYS/dev/cpuctl"; do
    [ -d "$d" ] && { printf '%s' "$d"; return 0; }
  done
  return 1
}

apply_schedtune() {
  on=$(cfg_read SCHEDTUNE)
  [ "$on" = "1" ] || { printf 'schedtune 未开启，跳过\n'; return 0; }
  base=$(stune_dir) || { printf '设备无 schedtune 节点\n'; return 0; }
  p=$(profile_of "$1")
  case "$p" in
    powersave) boost=0 ;;
    balanced) boost=5 ;;
    performance) boost=15 ;;
    gaming) boost=20 ;;
  esac
  n=0
  for g in top-app foreground background; do
    d="$base/$g"
    [ -d "$d" ] || continue
    if [ -f "$d/schedtune.boost" ]; then
      wrs "$d/schedtune.boost" "$boost" >/dev/null 2>&1 && n=$((n + 1))
    fi
    if [ -f "$d/schedtune.prefer_idle" ]; then
      case "$p" in
        gaming) wrs "$d/schedtune.prefer_idle" "1" >/dev/null 2>&1 ;;
        *) wrs "$d/schedtune.prefer_idle" "0" >/dev/null 2>&1 ;;
      esac
    fi
    if [ -f "$d/schedtune.uclamp.min" ]; then
      case "$p" in
        powersave) wrs "$d/schedtune.uclamp.min" "0" >/dev/null 2>&1 ;;
        balanced) wrs "$d/schedtune.uclamp.min" "10" >/dev/null 2>&1 ;;
        performance) wrs "$d/schedtune.uclamp.min" "20" >/dev/null 2>&1 ;;
        gaming) wrs "$d/schedtune.uclamp.min" "30" >/dev/null 2>&1 ;;
      esac
    fi
  done
  printf 'schedtune boost=%s (%s 处)\n' "$boost" "$n"
}

apply_tcp() {
  on=$(cfg_read TCP_TUNE)
  [ "$on" = "1" ] || { printf 'TCP 调优未开启，跳过\n'; return 0; }
  p=$(profile_of "$1")
  case "$p" in
    powersave) rmin=4096; rdef=65536; rmax=4194304; wmin=4096; wdef=16384; wmax=2097152 ;;
    balanced) rmin=4096; rdef=87380; rmax=6291456; wmin=4096; wdef=65536; wmax=4194304 ;;
    performance) rmin=8192; rdef=131072; rmax=8388608; wmin=4096; wdef=65536; wmax=4194304 ;;
    gaming) rmin=8192; rdef=262144; rmax=16777216; wmin=8192; wdef=131072; wmax=8388608 ;;
  esac
  n=0
  if [ -f "$SYS/proc/sys/net/ipv4/tcp_rmem" ]; then
    wrs "$SYS/proc/sys/net/ipv4/tcp_rmem" "$rmin $rdef $rmax" >/dev/null 2>&1 && n=$((n + 1))
  fi
  if [ -f "$SYS/proc/sys/net/ipv4/tcp_wmem" ]; then
    wrs "$SYS/proc/sys/net/ipv4/tcp_wmem" "$wmin $wdef $wmax" >/dev/null 2>&1 && n=$((n + 1))
  fi
  if [ -f "$SYS/proc/sys/net/core/netdev_max_backlog" ]; then
    case "$p" in
      powersave) v=1000 ;;
      balanced) v=3000 ;;
      performance) v=5000 ;;
      gaming) v=8000 ;;
    esac
    wrs "$SYS/proc/sys/net/core/netdev_max_backlog" "$v" >/dev/null 2>&1 && n=$((n + 1))
  fi
  if [ -f "$SYS/proc/sys/net/core/netdev_budget" ]; then
    case "$p" in
      powersave) v=300 ;;
      balanced) v=600 ;;
      performance) v=900 ;;
      gaming) v=1200 ;;
    esac
    wrs "$SYS/proc/sys/net/core/netdev_budget" "$v" >/dev/null 2>&1 && n=$((n + 1))
  fi
  if [ -f "$SYS/proc/sys/net/ipv4/tcp_moderate_rcvbuf" ]; then
    wrs "$SYS/proc/sys/net/ipv4/tcp_moderate_rcvbuf" "1" >/dev/null 2>&1 && n=$((n + 1))
  fi
  printf 'TCP 已调 %s 项 (rmem %s-%s-%s)\n' "$n" "$rmin" "$rdef" "$rmax"
}

apply_boost() {
  on=$(cfg_read BOOST)
  [ "$on" = "1" ] || { printf 'boost 未开启，跳过\n'; return 0; }
  p=$(profile_of "$1")
  case "$p" in
    powersave) ib=0 ;;
    balanced) ib=1190400 ;;
    performance) ib=1804800 ;;
    gaming) ib=2208000 ;;
  esac
  n=0
  for b in "$SYS/sys/module/cpu_boost/parameters" "$SYS/sys/module/msm_performance/parameters" \
           "$SYS/sys/module/cpu_input_boost/parameters" "$SYS/sys/module/input_boost/parameters"; do
    [ -d "$b" ] || continue
    for k in input_boost_freq input_boost_ms boost_freq boost_ms ib_freq ib_ms; do
      [ -f "$b/$k" ] || continue
      case "$k" in
        *freq*) wrs "$b/$k" "$ib" >/dev/null 2>&1 && n=$((n + 1)) ;;
        *) [ "$p" = "powersave" ] && wrs "$b/$k" "0" >/dev/null 2>&1 || wrs "$b/$k" "500" >/dev/null 2>&1 ;;
      esac
    done
    for k in touch_boost touch_boost_duration; do
      [ -f "$b/$k" ] || continue
      [ "$p" = "powersave" ] && wrs "$b/$k" "0" >/dev/null 2>&1 || wrs "$b/$k" "1" >/dev/null 2>&1
    done
  done
  printf 'boost 已调 %s 项 (freq %s)\n' "$n" "$ib"
}

apply_fs() {
  on=$(cfg_read FS_TUNE)
  [ "$on" = "1" ] || { printf 'fs 调优未开启，跳过\n'; return 0; }
  n=0
  for kv in "fs/inotify/max_user_watches=524288" "fs/inotify/max_user_instances=1024" \
            "fs/inotify/max_queued_events=32768" "fs/file-max=2097152" "fs/nr_open=2097152" \
            "fs/epoll/max_user_watches=262144" "fs/protected_fifos=0" "fs/protected_regular=0" \
            "fs/protected_hardlinks=0" "fs/protected_symlinks=0"; do
    k=${kv%%=*}
    v=${kv#*=}
    f="$SYS/proc/sys/$k"
    [ -f "$f" ] || continue
    wrs "$f" "$v" >/dev/null 2>&1 && n=$((n + 1))
  done
  printf 'fs 已调 %s 项\n' "$n"
}

status_all() {
  printf 'DEVFREQ   = %s\n' "$(cfg_read DEVFREQ)"
  printf 'KSM       = %s\n' "$(cfg_read KSM)"
  printf 'THP       = %s\n' "$(cfg_read THP)"
  printf 'SCHEDTUNE = %s\n' "$(cfg_read SCHEDTUNE)"
  printf 'TCP_TUNE  = %s\n' "$(cfg_read TCP_TUNE)"
  printf 'BOOST     = %s\n' "$(cfg_read BOOST)"
  printf 'FS_TUNE   = %s\n' "$(cfg_read FS_TUNE)"
  printf '内存      = %s MB\n' "$(mem_mb)"
  printf 'devfreq   = %s 个\n' "$(devfreq_dirs | wc -l | tr -d ' ')"
  printf 'stune     = %s\n' "$(stune_dir 2>/dev/null || printf '无')"
}

case "$1" in
  devfreq)
    apply_devfreq "$2"
    ;;
  devfreq-list)
    list_devfreq
    ;;
  ksm)
    apply_ksm
    ;;
  thp)
    apply_thp "$2"
    ;;
  schedtune)
    apply_schedtune "$2"
    ;;
  tcp)
    apply_tcp "$2"
    ;;
  boost)
    apply_boost "$2"
    ;;
  fs)
    apply_fs
    ;;
  all)
    apply_devfreq "$2"
    apply_ksm
    apply_thp "$2"
    apply_schedtune "$2"
    apply_tcp "$2"
    apply_boost "$2"
    apply_fs
    ;;
  status)
    status_all
    ;;
  *)
    printf 'usage: kernel.sh {devfreq|devfreq-list|ksm|thp|schedtune|tcp|boost|fs|all|status} [profile]\nprofile: powersave|balanced|performance|gaming\n'
    ;;
esac
