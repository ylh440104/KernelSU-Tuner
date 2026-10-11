#!/system/bin/sh

CFG_DIR=/data/adb/ksu_tuner
CFG=$CFG_DIR/config.conf
SYS=${KSU_SYS:-}

mkdir -p "$CFG_DIR" 2>/dev/null
[ -f "$CFG" ] || : > "$CFG"

get() {
  sed -n "s/^$1=//p" "$CFG" 2>/dev/null | tail -n 1
}

setkv() {
  sed -i "/^$1=/d" "$CFG" 2>/dev/null
  printf '%s=%s\n' "$1" "$2" >> "$CFG"
}

sh_run() {
  command -v settings >/dev/null 2>&1 || return 1
  settings "$@" >/dev/null 2>&1
}

get_refresh() {
  r=$(sh_run get system peak_refresh_rate && settings get system peak_refresh_rate 2>/dev/null)
  case "$r" in ''|null|*[!0-9.]*) r=$(get DISP_HZ) ;; esac
  [ -n "$r" ] || r="-"
  printf '%s' "$r"
}

get_min_refresh() {
  r=$(settings get system min_refresh_rate 2>/dev/null)
  case "$r" in ''|null|*[!0-9.]*) r="-" ;; esac
  printf '%s' "$r"
}

touch_nodes() {
  for p in \
    "$SYS"/sys/module/msm_performance/parameters/touch_boost \
    "$SYS"/sys/class/touch/touch_dev/boost_value \
    "$SYS"/sys/class/touch/touch_dev/game_mode \
    "$SYS"/sys/class/touch/touch_dev/fod_status \
    "$SYS"/proc/touchpanel/oppo_tp_game_switch \
    "$SYS"/proc/touchpanel/game_switch_enable \
    "$SYS"/sys/devices/virtual/touchscreen/touchscreen/report_rate \
    "$SYS"/sys/class/touchscreen/*/report_rate \
    "$SYS"/sys/kernel/touchpanel/*/report_rate
  do
    [ -f "$p" ] && printf '%s\n' "$p"
  done
}

apply_refresh() {
  prof=$1
  case "$prof" in
    powersave) hz=60 ;;
    balanced) hz=0 ;;
    performance) hz=120 ;;
    gaming) hz=144 ;;
  esac
  if [ "$hz" = "0" ]; then
    sh_run delete system peak_refresh_rate
    sh_run delete system min_refresh_rate
    return 0
  fi
  sh_run put system peak_refresh_rate "$hz"
  sh_run put system min_refresh_rate "$hz"
  setkv DISP_HZ "$hz"
}

apply_touch() {
  prof=$1
  case "$prof" in
    powersave) v=0 ;;
    balanced) v=0 ;;
    *) v=1 ;;
  esac
  for p in $(touch_nodes); do
    case "$p" in
      *report_rate*)
        case "$prof" in
          powersave) wr_val=120 ;;
          balanced) wr_val=180 ;;
          performance) wr_val=240 ;;
          gaming) wr_val=300 ;;
        esac
        ;;
      *) wr_val="$v" ;;
    esac
    bk_save "$p"
    chmod 0644 "$p" 2>/dev/null
    ( printf '%s' "$wr_val" > "$p" ) 2>/dev/null
  done
  setkv DISP_TOUCH "$v"
}

bk_save() {
  [ -f "$1" ] || return 0
  BAK=$CFG_DIR/backup.conf
  [ -f "$BAK" ] || : > "$BAK"
  grep -qF "$1|" "$BAK" 2>/dev/null && return 0
  v=$(head -n 1 "$1" 2>/dev/null)
  [ -n "$v" ] || return 0
  printf '%s|%s\n' "$1" "$v" >> "$BAK"
}

do_status() {
  printf 'DISP_HZ=%s\n' "$(get_refresh)"
  printf 'DISP_MIN_HZ=%s\n' "$(get_min_refresh)"
  t=$(get DISP_TOUCH)
  [ -n "$t" ] || t="-"
  printf 'DISP_TOUCH=%s\n' "$t"
  n=0
  for p in $(touch_nodes); do n=$((n + 1)); done
  printf 'DISP_TOUCH_NODES=%s\n' "$n"
  t=""
  for p in $(touch_nodes); do
    [ -n "$t" ] && t="$t,"
    t="$t$(head -n 1 "$p" 2>/dev/null)"
  done
  [ -n "$t" ] || t="-"
  printf 'DISP_TOUCH_VAL=%s\n' "$t"
  printf 'DISP_MAX_HZ=%s\n' "$(cat "$SYS"/sys/class/graphics/fb0/max_refresh_rate 2>/dev/null)"
}

case "$1" in
  status)
    do_status
    ;;
  refresh)
    apply_refresh "$2"
    printf '已设置刷新率档: %s\n' "$2"
    ;;
  touch)
    apply_touch "$2"
    printf '已设置触控档: %s\n' "$2"
    ;;
  apply)
    p=$2
    [ -n "$p" ] || p=$(get PROFILE)
    [ -n "$p" ] || p=balanced
    apply_refresh "$p"
    apply_touch "$p"
    printf '显示调优已应用: %s\n' "$p"
    ;;
  nodes)
    touch_nodes
    ;;
  *)
    printf 'usage: display.sh {status|refresh <profile>|touch <profile>|apply [profile]|nodes}\n'
    ;;
esac