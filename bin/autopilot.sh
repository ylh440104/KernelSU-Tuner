#!/system/bin/sh

CFG_DIR=/data/adb/ksu_tuner
CFG=$CFG_DIR/config.conf
PIDF=$CFG_DIR/autopilot.pid
LOGF=$CFG_DIR/autopilot.log
SYS=${KSU_SYS:-}

MODDIR=$(cd "${0%/*}" 2>/dev/null && cd .. && pwd)
[ -n "$MODDIR" ] || MODDIR=/data/adb/modules/KernelSU-Tuner
TUNER=$MODDIR/bin/tuner.sh

mkdir -p "$CFG_DIR" 2>/dev/null
[ -f "$CFG" ] || : > "$CFG"
[ -f "$LOGF" ] || : > "$LOGF"

get() {
  sed -n "s/^$1=//p" "$CFG" 2>/dev/null | tail -n 1
}

alog() {
  printf '%s %s\n' "$(date '+%m-%d %H:%M:%S')" "$*" >> "$LOGF" 2>/dev/null
  n=$(wc -l "$LOGF" 2>/dev/null | awk '{print $1}')
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  if [ "$n" -gt 200 ]; then
    tail -n 200 "$LOGF" > "$LOGF.t" 2>/dev/null
    mv -f "$LOGF.t" "$LOGF" 2>/dev/null
  fi
  return 0
}

max_temp() {
  best=0
  for z in "$SYS"/sys/class/thermal/thermal_zone*; do
    [ -d "$z" ] || continue
    v=$(cat "$z/temp" 2>/dev/null)
    case "$v" in ''|*[!0-9-]*) continue ;; esac
    if [ "$v" -gt "$best" ]; then best=$v; fi
  done
  printf '%s' "$best"
}

read_temp() {
  best=0
  for z in "$SYS"/sys/class/thermal/thermal_zone*; do
    [ -d "$z" ] || continue
    t=$(cat "$z/type" 2>/dev/null)
    case "$t" in
      *cpu*|*CPU*|*soc*|*SOC*|*tsens*|*gpu*|*GPU*|*battery*|*skin*|*therm*|*mtkts*) ;;
      *) continue ;;
    esac
    v=$(cat "$z/temp" 2>/dev/null)
    case "$v" in ''|*[!0-9-]*) continue ;; esac
    if [ "$v" -gt "$best" ]; then best=$v; fi
  done
  if [ "$best" -eq 0 ]; then
    best=$(max_temp)
  fi
  printf '%s' "$best"
}

read_screen() {
  for b in "$SYS"/sys/class/backlight/*/brightness; do
    [ -f "$b" ] || continue
    v=$(cat "$b" 2>/dev/null)
    case "$v" in ''|*[!0-9]*) continue ;; esac
    if [ "$v" -gt 0 ]; then printf '1'; else printf '0'; fi
    return 0
  done
  s=$(dumpsys power 2>/dev/null | grep -m1 'mWakefulness=')
  case "$s" in
    *Awake*) printf '1' ;;
    *) printf '0' ;;
  esac
}

read_lowpower() {
  v=$(settings get global low_power 2>/dev/null | tr -d ' \n\r')
  case "$v" in
    1) printf '1' ;;
    *) printf '0' ;;
  esac
}

read_charging() {
  for p in "$SYS"/sys/class/power_supply/*/status; do
    [ -f "$p" ] || continue
    v=$(cat "$p" 2>/dev/null)
    case "$v" in
      Charging|Full) printf '1'; return 0 ;;
    esac
  done
  printf '0'
}

in_window() {
  win=$(get AUTO_WINDOW)
  [ -n "$win" ] || return 1
  case "$win" in
    *-*) ;;
    *) return 1 ;;
  esac
  st=${win%-*}
  en=${win#*-}
  now=$(date '+%H%M' 2>/dev/null)
  case "$now" in ''|*[!0-9]*) return 1 ;; esac
  st=$(printf '%s' "$st" | tr -d ':')
  en=$(printf '%s' "$en" | tr -d ':')
  st=$(printf '%04d' "${st:-0}" 2>/dev/null)
  en=$(printf '%04d' "${en:-0}" 2>/dev/null)
  case "$st" in *[!0-9]*) return 1 ;; esac
  case "$en" in *[!0-9]*) return 1 ;; esac
  if [ "$st" -le "$en" ]; then
    [ "$now" -ge "$st" ] && [ "$now" -lt "$en" ] && return 0
  else
    if [ "$now" -ge "$st" ] || [ "$now" -lt "$en" ]; then return 0; fi
  fi
  return 1
}

decide() {
  d_base=$(get AUTO_BASE)
  [ -n "$d_base" ] || d_base=$(get PROFILE)
  [ -n "$d_base" ] || d_base=balanced
  d_cool=$(get AUTO_COOL)
  [ -n "$d_cool" ] || d_cool=powersave
  d_hot=$(get AUTO_TEMP_HIGH)
  [ -n "$d_hot" ] || d_hot=45000
  d_ok=$(get AUTO_TEMP_LOW)
  [ -n "$d_ok" ] || d_ok=40000
  d_sc=$(get AUTO_SCREEN)
  [ -n "$d_sc" ] || d_sc=1
  d_cg=$(get AUTO_CHARGE)
  [ -n "$d_cg" ] || d_cg=0

  t=$(read_temp)
  case "$t" in ''|*[!0-9]*) t=0 ;; esac
  if [ "$t" -gt 0 ] && [ "$t" -lt 200 ]; then t=$((t * 1000)); fi
  sc=$(read_screen)
  ch=$(read_charging)
  tc=$((t / 1000))
  lp=$(read_lowpower)
  d_lp=$(get AUTO_LOWPOWER)
  [ -n "$d_lp" ] || d_lp=0
  d_wprof=$(get AUTO_WINDOW_PROFILE)
  d_won=$(get AUTO_WINDOW_ON)
  [ -n "$d_won" ] || d_won=0
  if [ "$d_won" = "1" ] && [ -n "$d_wprof" ] && in_window; then
    printf '%s|%s|%s|%s\n' "$d_wprof" "$tc" "定时" "0"
    return 0
  fi
  if [ "$lp" = "1" ] && [ "$d_lp" = "1" ]; then
    printf '%s|%s|%s|%s\n' "powersave" "$tc" "省电模式" "0"
    return 0
  fi

  if [ "$t" -ge "$d_hot" ]; then
    printf '%s|%s|%s|%s\n' "$d_cool" "$tc" "过热" "1"
  elif [ "$sc" = "0" ] && [ "$d_sc" = "1" ]; then
    printf '%s|%s|%s|%s\n' "$d_cool" "$tc" "息屏" "0"
  elif [ "$ch" = "1" ] && [ "$d_cg" = "1" ]; then
    printf '%s|%s|%s|%s\n' "performance" "$tc" "充电" "0"
  else
    printf '%s|%s|%s|%s\n' "$d_base" "$tc" "常规" "0"
  fi
}

run_loop() {
  cooling=0
  last=""
  alog "启动"
  while :; do
    out=$(decide)
    target=$(printf '%s' "$out" | cut -d'|' -f1)
    tc=$(printf '%s' "$out" | cut -d'|' -f2)
    why=$(printf '%s' "$out" | cut -d'|' -f3)
    hotflag=$(printf '%s' "$out" | cut -d'|' -f4)
    low=$(get AUTO_TEMP_LOW)
    [ -n "$low" ] || low=40000
    low=$((low / 1000))

    if [ "$hotflag" = "1" ]; then
      cooling=1
    elif [ "$cooling" = "1" ]; then
      if [ "$tc" -le "$low" ]; then
        cooling=0
        why="已降温"
      else
        target=$(get AUTO_COOL)
        [ -n "$target" ] || target=powersave
        why="冷却中"
      fi
    fi

    if [ "$target" != "$last" ]; then
      sh "$TUNER" apply "$target" >/dev/null 2>&1
      alog "$last -> $target (${why} ${tc}C)"
      last="$target"
    fi

    sleep 5
  done
}

case "$1" in
  start)
    if [ -f "$PIDF" ]; then
      p=$(cat "$PIDF" 2>/dev/null)
      if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
        printf 'AutoPilot 已在运行 PID=%s\n' "$p"
        exit 0
      fi
    fi
    nohup sh "$0" run >/dev/null 2>&1 &
    printf '%s' "$!" > "$PIDF"
    printf 'AutoPilot 已启动 PID=%s\n' "$!"
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
    alog "已停止"
    printf 'AutoPilot 已停止\n'
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
  once)
    out=$(decide)
    printf 'TARGET=%s\n' "$(printf '%s' "$out" | cut -d'|' -f1)"
    printf 'TEMP=%s\n' "$(printf '%s' "$out" | cut -d'|' -f2)"
    printf 'REASON=%s\n' "$(printf '%s' "$out" | cut -d'|' -f3)"
    printf 'HOT=%s\n' "$(printf '%s' "$out" | cut -d'|' -f4)"
    ;;
  run)
    run_loop
    ;;
  *)
    printf 'usage: autopilot.sh {start|stop|status|once|run}\n'
    ;;
esac