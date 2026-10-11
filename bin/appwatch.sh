#!/system/bin/sh

CFG_DIR=/data/adb/ksu_tuner
CFG=$CFG_DIR/config.conf
RULES=$CFG_DIR/apprules.conf
PIDF=$CFG_DIR/appwatch.pid
LOGF=$CFG_DIR/appwatch.log
SYS=${KSU_SYS:-}

MODDIR=$(cd "${0%/*}" 2>/dev/null && cd .. && pwd)
[ -n "$MODDIR" ] || MODDIR=/data/adb/modules/KernelSU-Tuner
TUNER=$MODDIR/bin/tuner.sh

mkdir -p "$CFG_DIR" 2>/dev/null
[ -f "$CFG" ] || : > "$CFG"
[ -f "$RULES" ] || : > "$RULES"
[ -f "$LOGF" ] || : > "$LOGF"

get() {
  sed -n "s/^$1=//p" "$CFG" 2>/dev/null | tail -n 1
}

wlog() {
  printf '%s %s\n' "$(date '+%m-%d %H:%M:%S')" "$*" >> "$LOGF" 2>/dev/null
  n=$(wc -l "$LOGF" 2>/dev/null | awk '{print $1}')
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  if [ "$n" -gt 200 ]; then
    tail -n 200 "$LOGF" > "$LOGF.t" 2>/dev/null
    mv -f "$LOGF.t" "$LOGF" 2>/dev/null
  fi
  return 0
}

fg_pkg() {
  out=$(dumpsys activity activities 2>/dev/null | grep -m1 -E 'mResumedActivity|topResumedActivity')
  p=$(printf '%s' "$out" | sed -n 's/.*[ {]\([A-Za-z0-9_.]*\)\/[A-Za-z0-9_.$]*.*/\1/p')
  [ -n "$p" ] && { printf '%s' "$p"; return 0; }
  out=$(dumpsys window 2>/dev/null | grep -m1 -E 'mCurrentFocus|mFocusedApp')
  p=$(printf '%s' "$out" | sed -n 's/.*[ {]\([A-Za-z0-9_.]*\)\/[A-Za-z0-9_.$]*.*/\1/p')
  [ -n "$p" ] && { printf '%s' "$p"; return 0; }
  out=$(dumpsys activity top 2>/dev/null | grep -m1 'ACTIVITY')
  p=$(printf '%s' "$out" | sed -n 's/.*[ {]\([A-Za-z0-9_.]*\)\/[A-Za-z0-9_.$]*.*/\1/p')
  printf '%s' "$p"
}

rule_of() {
  [ -n "$1" ] || return 1
  awk -F'|' -v p="$1" '$1==p {v=$2} END {if (v!="") print v}' "$RULES" 2>/dev/null
}

run_loop() {
  last=""
  wlog "启动"
  while :; do
    base=$(get WATCH_BASE)
    [ -n "$base" ] || base=$(get PROFILE)
    [ -n "$base" ] || base=balanced
    fg=$(fg_pkg)
    if [ -n "$fg" ]; then
      r=$(rule_of "$fg")
      if [ -n "$r" ]; then
        target="$r"
        name="$fg"
      else
        target="$base"
        name="默认"
      fi
      if [ "$target" != "$last" ]; then
        sh "$TUNER" apply "$target" >/dev/null 2>&1
        wlog "$name -> $target"
        last="$target"
      fi
    fi
    sleep 3
  done
}

case "$1" in
  start)
    if [ -f "$PIDF" ]; then
      p=$(cat "$PIDF" 2>/dev/null)
      if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
        printf 'AppWatch 已在运行 PID=%s\n' "$p"
        exit 0
      fi
    fi
    nohup sh "$0" run >/dev/null 2>&1 &
    printf '%s' "$!" > "$PIDF"
    printf 'AppWatch 已启动 PID=%s\n' "$!"
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
    wlog "已停止"
    printf 'AppWatch 已停止\n'
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
  fg)
    fg_pkg
    printf '\n'
    ;;
  once)
    fg=$(fg_pkg)
    r=$(rule_of "$fg")
    printf 'FOREGROUND=%s\n' "$fg"
    printf 'RULE=%s\n' "$r"
    ;;
  rules)
    cat "$RULES" 2>/dev/null
    ;;
  set)
    [ -n "$1" ] || exit 1
    [ -n "$2" ] || exit 1
    awk -F'|' -v p="$2" '$1!=p {print}' "$RULES" > "$RULES.t" 2>/dev/null
    mv -f "$RULES.t" "$RULES" 2>/dev/null
    printf '%s|%s\n' "$2" "$3" >> "$RULES"
    printf 'OK %s=%s\n' "$2" "$3"
    ;;
  del)
    [ -n "$2" ] || exit 1
    awk -F'|' -v p="$2" '$1!=p {print}' "$RULES" > "$RULES.t" 2>/dev/null
    mv -f "$RULES.t" "$RULES" 2>/dev/null
    printf 'OK\n'
    ;;
  run)
    run_loop
    ;;
  *)
    printf 'usage: appwatch.sh {start|stop|status|fg|once|rules|set <pkg> <profile>|del <pkg>|run}\n'
    ;;
esac