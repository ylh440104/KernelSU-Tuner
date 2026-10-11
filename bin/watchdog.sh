#!/system/bin/sh

CFG_DIR=/data/adb/ksu_tuner
CFG=$CFG_DIR/config.conf
LOG=$CFG_DIR/watchdog.log
PIDF=$CFG_DIR/watchdog.pid
MODDIR=$(cd "${0%/*}" 2>/dev/null && cd .. && pwd)
[ -n "$MODDIR" ] || MODDIR=/data/adb/modules/KernelSU-Tuner
MAXLOG=200

mkdir -p "$CFG_DIR" 2>/dev/null

cfg_read() {
  [ -f "$CFG" ] || return 1
  sed -n "s/^$1=//p" "$CFG" 2>/dev/null | tail -n 1
}

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

alive() {
  f="$CFG_DIR/$1.pid"
  [ -f "$f" ] || return 1
  p=$(head -n 1 "$f" 2>/dev/null)
  case "$p" in ''|*[!0-9]*) return 1 ;; esac
  [ -d "/proc/$p" ] || return 1
  return 0
}

start_one() {
  n=$1
  script="$MODDIR/bin/$n.sh"
  [ -x "$script" ] || return 0
  alive "$n" && return 0
  log "restart $n"
  ( sh "$script" start >/dev/null 2>&1 ) &
  return 0
}

do_run() {
  while :; do
    on=$(cfg_read WATCHDOG)
    [ "$on" = "1" ] || break
    start_one autopilot
    start_one guard
    start_one appwatch
    start_one wipeshield
    i=0
    while [ "$i" -lt 30 ]; do
      sleep 10
      i=$((i + 1))
    done
  done
  rm -f "$PIDF" 2>/dev/null
}

do_start() {
  alive watchdog && { printf '已在运行\n'; return 0; }
  on=$(cfg_read WATCHDOG)
  [ "$on" = "1" ] || { printf '看门狗未开启\n'; return 0; }
  ( do_run >/dev/null 2>&1 ) &
  p=$!
  printf '%s\n' "$p" > "$PIDF" 2>/dev/null
  log "start pid=$p"
  printf '已启动 pid=%s\n' "$p"
}

do_stop() {
  if [ -f "$PIDF" ]; then
    p=$(head -n 1 "$PIDF" 2>/dev/null)
    case "$p" in ''|*[!0-9]*) ;; *) kill "$p" 2>/dev/null ;; esac
  fi
  rm -f "$PIDF" 2>/dev/null
  printf '已停止\n'
}

do_status() {
  if alive watchdog; then
    printf '看门狗 运行中 pid=%s\n' "$(head -n 1 "$PIDF" 2>/dev/null)"
  else
    printf '看门狗 未运行\n'
  fi
  for n in autopilot guard appwatch wipeshield; do
    if alive "$n"; then
      printf '  %-10s 运行中\n' "$n"
    else
      printf '  %-10s 停止\n' "$n"
    fi
  done
}

case "$1" in
  start)
    do_start
    ;;
  stop)
    do_stop
    ;;
  status)
    do_status
    ;;
  log)
    tail -n 40 "$LOG" 2>/dev/null
    ;;
  *)
    printf 'usage: watchdog.sh {start|stop|status|log}\n'
    ;;
esac
