#!/system/bin/sh

CFG_DIR=/data/adb/ksu_tuner
CFG=$CFG_DIR/config.conf
WLDIR=$CFG_DIR/wl
PIDF=$CFG_DIR/shield.pid
LOGF=$CFG_DIR/shield.log
SIGF=$CFG_DIR/shield.signal

mkdir -p "$WLDIR" 2>/dev/null
[ -f "$LOGF" ] || : > "$LOGF"

log() {
  printf '%s %s\n' "$(date '+%m-%d %H:%M:%S')" "$*" >> "$LOGF" 2>/dev/null
  n=$(wc -l "$LOGF" 2>/dev/null | awk '{print $1}')
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  if [ "$n" -gt 300 ]; then
    tail -n 300 "$LOGF" > "$LOGF.t" 2>/dev/null
    mv -f "$LOGF.t" "$LOGF" 2>/dev/null
  fi
  return 0
}

get() {
  sed -n "s/^$1=//p" "$CFG" 2>/dev/null | tail -n 1
}

setkv() {
  sed -i "/^$1=/d" "$CFG" 2>/dev/null
  printf '%s=%s\n' "$1" "$2" >> "$CFG"
}

mode_name() {
  case "$1" in
    1) printf 'strict' ;;
    2) printf 'normal' ;;
    *) printf 'off' ;;
  esac
}

mode_desc() {
  case "$1" in
    1) printf '增强模式：检测到立即终止' ;;
    2) printf '普通模式：检测到先询问' ;;
    *) printf '不防护' ;;
  esac
}

suspicious_cmd() {
  c=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
  [ -n "$c" ] || return 1

  case "$c" in
    *rm*|*mkfs*|*dd*|*shred*|*fastboot*|*wipe*|*flash*|*mv*|*chmod*) ;;
    *) return 1 ;;
  esac

  case "$c" in
    "rm -rf /"|"rm -fr /"|"rm -r /"|"rm -f /"|"rm -rf /*"|"rm -fr /*") return 0 ;;
    *"rm -rf --no-preserve-root"*) return 0 ;;
    *"rm -rf / "*|*"rm -fr / "*) return 0 ;;
  esac

  case "$c" in
    *"mkfs."*|*"mkfs "*)
      case "$c" in
        *"/dev/block"*|*"/dev/sd"*|*"by-name"*) return 0 ;;
      esac
      ;;
  esac

  case "$c" in
    *"dd "*"of=/dev/block"*) return 0 ;;
    *"of=/dev/block/by-name"*) return 0 ;;
    *"of=/dev/sd"*) return 0 ;;
  esac

  case "$c" in
    *"fastboot erase"*|*"fastboot -w"*|*"fastboot format"*) return 0 ;;
    *"fastboot flash"*) return 0 ;;
    *"wipe data"*|*"wipe all"*|*"--wipe_data"*) return 0 ;;
    *"shred /dev/block"*) return 0 ;;
  esac

  case "$c" in
    *"chmod -r 000 /"*) return 0 ;;
    *"chmod -r 000 /*"*) return 0 ;;
  esac

  case "$c" in
    *"mv /data "*|*"mv /sdcard "*|*"mv /system "*|*"mv /storage "*) return 0 ;;
  esac

  case "$c" in
    *"rm -rf"*|*"rm -fr"*|*"rm -r"*|*"rm -f"*)
      for tok in $c; do
        case "$tok" in
          /*)
            protected_path "$tok" && return 0
            ;;
        esac
      done
      ;;
  esac

  return 1
}

protected_path() {
  p=$(printf '%s' "$1")
  case "$p" in
    /data/local/tmp|/data/local/tmp/*|/data/media|/data/media/*|/tmp|/tmp/*|/cache|/cache/*) return 1 ;;
    /data|/data/*) return 0 ;;
    /system|/system/*|/vendor|/vendor/*|/product|/product/*) return 0 ;;
    /sdcard|/sdcard/*|/storage|/storage/*|/mnt|/mnt/*) return 0 ;;
    /boot|/boot/*|/persist|/persist/*|/metadata|/metadata/*) return 0 ;;
    /dev/block|/dev/block/*) return 0 ;;
  esac
  return 1
}

kill_proc() {
  p=$1
  [ -n "$p" ] || return 0
  case "$p" in ''|*[!0-9]*) return 0 ;; esac
  [ "$p" = "1" ] && return 0
  [ "$p" = "$$" ] && return 0
  cmd=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)
  [ -n "$cmd" ] || return 0
  case "$cmd" in
    *wipeshield*|*ksu_tuner*|*KernelSU-Tuner*|*tuner.sh*) return 0 ;;
  esac
  kill -9 "$p" 2>/dev/null
  log "KILLED pid=$p cmd=$cmd"
  return 0
}

handle() {
  cmd=$1
  pid=$2
  mode=$3
  case "$mode" in
    1)
      kill_proc "$pid"
      printf '%s|strict|%s\n' "$(date '+%H:%M:%S')" "$cmd" >> "$SIGF" 2>/dev/null
      log "STRICT blocked pid=$pid cmd=$cmd"
      ;;
    2)
      printf '%s|normal|%s|%s\n' "$(date '+%H:%M:%S')" "$pid" "$cmd" > "$SIGF" 2>/dev/null
      log "NORMAL detected pid=$pid cmd=$cmd (awaiting user)"
      ;;
    *)
      log "OFF would-be-blocked pid=$pid cmd=$cmd"
      ;;
  esac
  return 0
}

scan_proc() {
  mode=$1
  found=0
  for d in /proc/[0-9]*; do
    [ -d "$d" ] || continue
    p=${d#/proc/}
    [ "$p" = "$$" ] && continue
    [ "$p" = "1" ] && continue
    c=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
    [ -n "$c" ] || continue
    case "$c" in
      *wipeshield*|*ksu_tuner*|*KernelSU-Tuner*) continue ;;
    esac
    if suspicious_cmd "$c"; then
      handle "$c" "$p" "$mode"
      found=1
    fi
  done
  return 0
}

scan_files() {
  mode=$1
  for f in /data/adb/service.d/*.sh /data/adb/post-fs-data.d/*.sh; do
    [ -f "$f" ] || continue
    [ -s "$f" ] || continue
    if grep -qiE 'rm[[:space:]]+-[rf]*[[:space:]]+/(data|system|sdcard|storage|vendor|persist|metadata)|mkfs\.|dd[[:space:]]+if=/dev/(zero|urandom)|fastboot[[:space:]]+(erase|format|-w)|wipe[[:space:]]+(data|all)|of=/dev/block/by-name' "$f" 2>/dev/null; then
      case "$f" in
        *wipeshield*|*KernelSU-Tuner*) continue ;;
      esac
      handle "script:$f" "" "$mode"
    fi
  done
  return 0
}

resolve_pending() {
  [ -f "$SIGF" ] || return 0
  line=$(tail -n 1 "$SIGF" 2>/dev/null)
  case "$line" in
    *'|normal|'*) ;;
    *) return 0 ;;
  esac
  ans=$(get GUARD_ANSWER)
  case "$ans" in
    kill)
      p=$(printf '%s' "$line" | cut -d'|' -f3)
      kill_proc "$p"
      log "USER chose KILL for pid=$p"
      setkv GUARD_ANSWER pending
      ;;
    allow)
      log "USER chose ALLOW, added exception"
      p=$(printf '%s' "$line" | cut -d'|' -f3)
      c=$(printf '%s' "$line" | cut -d'|' -f4-)
      [ -n "$c" ] && printf '%s\n' "$c" >> "$WLDIR/allow.txt"
      setkv GUARD_ANSWER pending
      ;;
  esac
  return 0
}

run_loop() {
  log "shield started mode=$(mode_name "$(get GUARD_MODE)")"
  while :; do
    mode=$(get GUARD_MODE)
    [ -n "$mode" ] || mode=3
    case "$mode" in
      1|2) resolve_pending ;;
    esac
    if [ "$mode" = "1" ] || [ "$mode" = "2" ]; then
      if [ "$(get GUARD_PATTERN)" = "1" ]; then
        scan_proc "$mode"
      fi
      scan_files "$mode"
    fi
    sleep 2
  done
}

case "$1" in
  start)
    if [ -f "$PIDF" ]; then
      p=$(cat "$PIDF" 2>/dev/null)
      if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
        printf '防护已在运行 PID=%s\n' "$p"
        exit 0
      fi
    fi
    nohup sh "$0" run >/dev/null 2>&1 &
    printf '%s' "$!" > "$PIDF"
    printf '防护已启动 PID=%s\n' "$!"
    ;;
  stop)
    if [ -f "$PIDF" ]; then
      p=$(cat "$PIDF" 2>/dev/null)
      [ -n "$p" ] && kill "$p" 2>/dev/null
      rm -f "$PIDF"
    fi
    log "shield stopped"
    printf '防护已停止\n'
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
  mode)
    m=$2
    case "$m" in
      1|2|3) setkv GUARD_MODE "$m"; printf 'OK mode=%s\n' "$m" ;;
      *) printf 'usage: wipeshield.sh mode {1|2|3}\n' ;;
    esac
    ;;
  answer)
    a=$2
    case "$a" in
      kill|allow) setkv GUARD_ANSWER "$a"; printf 'OK %s\n' "$a" ;;
      *) printf 'usage: wipeshield.sh answer {kill|allow}\n' ;;
    esac
    ;;
  signal)
    if [ -f "$SIGF" ]; then
      tail -n 1 "$SIGF"
    else
      printf '\n'
    fi
    ;;
  test)
    c="$2"
    if suspicious_cmd "$c"; then
      printf 'BLOCK\n'
    else
      printf 'PASS\n'
    fi
    ;;
  log)
    tail -n 60 "$LOGF" 2>/dev/null
    ;;
  run)
    run_loop
    ;;
  *)
    printf 'usage: wipeshield.sh {start|stop|status|mode 1|2|3|answer kill|allow|signal|test <cmd>|log|run}\n'
    ;;
esac
