#!/system/bin/sh

MODDIR=${0%/*}
CFG_DIR=/data/adb/ksu_tuner
CFG=$CFG_DIR/config.conf
LOG=$CFG_DIR/tuner.log

get() {
  sed -n "s/^$1=//p" "$CFG" 2>/dev/null | tail -n 1
}

setkv() {
  sed -i "/^$1=/d" "$CFG" 2>/dev/null
  printf '%s=%s\n' "$1" "$2" >> "$CFG"
}

lg() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null
}

ap=$(get AUTOPILOT)
bg=$(get BATT_GUARD)
aw=$(get APPWATCH)

if [ "$ap" = "1" ] && [ "$bg" = "1" ] && [ "$aw" = "1" ]; then
  setkv AUTOPILOT 0
  setkv BATT_GUARD 0
  setkv APPWATCH 0
  sh "$MODDIR/bin/autopilot.sh" stop >/dev/null 2>&1
  sh "$MODDIR/bin/guard.sh" stop >/dev/null 2>&1
  sh "$MODDIR/bin/appwatch.sh" stop >/dev/null 2>&1
  sh "$MODDIR/bin/appctl.sh" restore >/dev/null 2>&1
  lg "动作按钮: 全部关闭"
  printf '已关闭: 智能驾驶 + 电池守护 + 应用追踪\n'
  printf '应用待机已恢复 frequent\n'
  exit 0
fi

if [ "$ap" = "1" ] && [ "$bg" = "1" ]; then
  setkv BATT_GUARD 0
  sh "$MODDIR/bin/guard.sh" stop >/dev/null 2>&1
  setkv APPWATCH 1
  sh "$MODDIR/bin/appwatch.sh" start >/dev/null 2>&1
  lg "动作按钮: 切换为应用追踪"
  printf '已切换: 应用性能追踪\n'
  printf '规则数: %s\n' "$(wc -l "$CFG_DIR/apprules.conf" 2>/dev/null | awk '{print $1}')"
  exit 0
fi

if [ "$ap" = "1" ]; then
  setkv AUTOPILOT 0
  sh "$MODDIR/bin/autopilot.sh" stop >/dev/null 2>&1
  setkv BATT_GUARD 1
  sh "$MODDIR/bin/guard.sh" start >/dev/null 2>&1
  sh "$MODDIR/bin/appctl.sh" optimize >/dev/null 2>&1
  lg "动作按钮: 切换为电池守护"
  printf '已切换: 电池守护\n'
  printf '充电上限: %s%%\n' "$(get CHARGE_LIMIT)"
  exit 0
fi

if [ "$bg" = "1" ]; then
  setkv BATT_GUARD 0
  sh "$MODDIR/bin/guard.sh" stop >/dev/null 2>&1
  cur=$(get PROFILE)
  case "$cur" in
    powersave) next=balanced ;;
    balanced) next=performance ;;
    performance) next=gaming ;;
    *) next=powersave ;;
  esac
  sh "$MODDIR/bin/tuner.sh" fast "$next" >/dev/null 2>&1
  lg "动作按钮: 切换预设 $cur -> $next"
  printf '已切换预设: %s -> %s\n' "$cur" "$next"
  exit 0
fi

if [ "$aw" = "1" ]; then
  setkv APPWATCH 0
  sh "$MODDIR/bin/appwatch.sh" stop >/dev/null 2>&1
  cur=$(get PROFILE)
  case "$cur" in
    powersave) next=balanced ;;
    balanced) next=performance ;;
    performance) next=gaming ;;
    *) next=powersave ;;
  esac
  sh "$MODDIR/bin/tuner.sh" fast "$next" >/dev/null 2>&1
  lg "动作按钮: 关闭追踪并切换预设 $cur -> $next"
  printf '已关闭追踪，切换预设: %s -> %s\n' "$cur" "$next"
  exit 0
fi

setkv AUTOPILOT 1
sh "$MODDIR/bin/autopilot.sh" start >/dev/null 2>&1
lg "动作按钮: 启动智能驾驶"
printf '已启动: 智能驾驶\n'
printf '基准预设: %s\n' "$(get AUTO_BASE)"
printf '过热阈值: %s C\n' "$(( $(get AUTO_TEMP_HIGH) / 1000 ))"