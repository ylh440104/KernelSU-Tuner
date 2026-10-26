#!/system/bin/sh

CFG_DIR=/data/adb/ksu_tuner
CFG=$CFG_DIR/config.conf
PIDF=$CFG_DIR/guard.pid
LOGF=$CFG_DIR/guard.log
SYS=${KSU_SYS:-}

mkdir -p "$CFG_DIR" 2>/dev/null
[ -f "$CFG" ] || : > "$CFG"
[ -f "$LOGF" ] || : > "$LOGF"

get() {
  sed -n "s/^$1=//p" "$CFG" 2>/dev/null | tail -n 1
}

glog() {
  printf '%s %s\n' "$(date '+%m-%d %H:%M:%S')" "$*" >> "$LOGF" 2>/dev/null
  n=$(wc -l "$LOGF" 2>/dev/null | awk '{print $1}')
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  if [ "$n" -gt 200 ]; then
    tail -n 200 "$LOGF" > "$LOGF.t" 2>/dev/null
    mv -f "$LOGF.t" "$LOGF" 2>/dev/null
  fi
  return 0
}

find_node() {
  for n in charging_enabled input_suspend batt_slate_mode store_mode charge_disable; do
    for p in "$SYS"/sys/class/power_supply/*/"$n"; do
      [ -f "$p" ] && { printf '%s' "$p"; return 0; }
    done
  done
  return 1
}

allow_val() {
  case "$1" in
    */charging_enabled) printf '1' ;;
    */charge_disable) printf '0' ;;
    *) printf '0' ;;
  esac
}

block_val() {
  case "$1" in
    */charging_enabled) printf '0' ;;
    */charge_disable) printf '1' ;;
    *) printf '1' ;;
  esac
}

set_charge() {
  v=$(allow_val "$1")
  [ "$2" = "0" ] && v=$(block_val "$1")
  ( printf '%s' "$v" > "$1" ) 2>/dev/null
}

read_cap() {
  for p in "$SYS"/sys/class/power_supply/battery/capacity "$SYS"/sys/class/power_supply/*/capacity; do
    [ -f "$p" ] || continue
    v=$(cat "$p" 2>/dev/null)
    case "$v" in ''|*[!0-9]*) continue ;; esac
    printf '%s' "$v"
    return 0
  done
  printf '0'
}

read_chg() {
  for p in "$SYS"/sys/class/power_supply/*/status; do
    [ -f "$p" ] || continue
    v=$(cat "$p" 2>/dev/null)
    case "$v" in
      Charging|Full) printf '1'; return 0 ;;
    esac
  done
  printf '0'
}

run_loop() {
  node=$(find_node)
  if [ -z "$node" ]; then
    glog "未找到充电控制节点"
    printf 'unsupported\n'
    exit 1
  fi
  limit=$(get CHARGE_LIMIT)
  [ -n "$limit" ] || limit=80
  case "$limit" in ''|*[!0-9]*) limit=80 ;; esac
  [ "$limit" -gt 100 ] && limit=100
  [ "$limit" -lt 40 ] && limit=40
  low=$((limit - 3))
  state=-1
  glog "启动 node=$node limit=$limit"

  while :; do
    cap=$(read_cap)
    chg=$(read_chg)
    case "$cap" in ''|*[!0-9]*) cap=0 ;; esac
    if [ "$chg" = "1" ] && [ "$cap" -ge "$limit" ]; then
      if [ "$state" != "0" ]; then
        set_charge "$node" 0
        glog "停止充电 cap=${cap}%"
        state=0
      fi
    elif [ "$cap" -le "$low" ]; then
      if [ "$state" != "1" ]; then
        set_charge "$node" 1
        glog "恢复充电 cap=${cap}%"
        state=1
      fi
    fi
    sleep 30
  done
}

case "$1" in
  start)
    if [ -f "$PIDF" ]; then
      p=$(cat "$PIDF" 2>/dev/null)
      if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
        printf 'BatteryGuard 已在运行 PID=%s\n' "$p"
        exit 0
      fi
    fi
    nohup sh "$0" run >/dev/null 2>&1 &
    printf '%s' "$!" > "$PIDF"
    printf 'BatteryGuard 已启动 PID=%s\n' "$!"
    ;;
  stop)
    if [ -f "$PIDF" ]; then
      p=$(cat "$PIDF" 2>/dev/null)
      if [ -n "$p" ]; then
        kill "$p" 2>/dev/null
        sleep 1
        kill -9 "$p" 2>/dev/null
      fi
      rm -f "$PIDF"
    fi
    node=$(find_node)
    [ -n "$node" ] && set_charge "$node" 1
    glog "已停止，恢复充电"
    printf 'BatteryGuard 已停止\n'
    ;;
  status)
    if [ -f "$PIDF" ]; then
      p=$(cat "$PIDF" 2>/dev/null)
      if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
        printf 'running %s\n' "$p"
        exit 0
      fi
    fi
    printf 'stopped\n'
    ;;
  node)
    find_node
    printf '\n'
    ;;
  run)
    run_loop
    ;;
  *)
    printf 'usage: guard.sh {start|stop|status|node|run}\n'
    ;;
esac