#!/system/bin/sh

CFG_DIR=/data/adb/ksu_tuner
CFG=$CFG_DIR/config.conf
WL=$CFG_DIR/whitelist.txt

mkdir -p "$CFG_DIR" 2>/dev/null
[ -f "$CFG" ] || : > "$CFG"
[ -f "$WL" ] || : > "$WL"

in_wl() {
  [ -s "$WL" ] || return 1
  grep -qxF "$1" "$WL" 2>/dev/null
}

user_pkgs() {
  pm list packages -3 -e 2>/dev/null | sed 's/^package://' | sort
}

bucket_name() {
  case "$1" in
    10) printf 'active' ;;
    20) printf 'working' ;;
    30) printf 'frequent' ;;
    40) printf 'rare' ;;
    45) printf 'restricted' ;;
    50) printf 'never' ;;
    *) printf 'unknown' ;;
  esac
}

bucket_code() {
  case "$1" in
    active) printf '10' ;;
    working) printf '20' ;;
    frequent) printf '30' ;;
    rare) printf '40' ;;
    restricted) printf '45' ;;
    never) printf '50' ;;
    *) printf '30' ;;
  esac
}

foreground_pkg() {
  dumpsys activity activities 2>/dev/null | grep -m1 'mResumedActivity' | sed -n 's/.*u[0-9]* \([^ ]*\)\/.*/\1/p'
}

do_list() {
  for p in $(user_pkgs); do
    b=$(am get-standby-bucket "$p" 2>/dev/null | head -n 1)
    case "$b" in ''|*[!0-9]*) b=0 ;; esac
    w=0
    in_wl "$p" && w=1
    printf '%s|%s|%s\n' "$p" "$(bucket_name "$b")" "$w"
  done
}

do_set() {
  [ -n "$1" ] || return 1
  c=$(bucket_code "$2")
  am set-standby-bucket "$1" "$c" >/dev/null 2>&1
  printf 'OK %s %s\n' "$1" "$2"
}

do_optimize() {
  n=0
  for p in $(user_pkgs); do
    in_wl "$p" && continue
    am set-standby-bucket "$p" 40 >/dev/null 2>&1
    n=$((n + 1))
  done
  printf '已将 %s 个应用设为 rare\n' "$n"
}

do_restore() {
  n=0
  for p in $(user_pkgs); do
    in_wl "$p" && continue
    am set-standby-bucket "$p" 30 >/dev/null 2>&1
    n=$((n + 1))
  done
  printf '已将 %s 个应用恢复为 frequent\n' "$n"
}

do_hibernate() {
  fg=$(foreground_pkg)
  n=0
  for p in $(user_pkgs); do
    in_wl "$p" && continue
    [ "$p" = "$fg" ] && continue
    am force-stop "$p" >/dev/null 2>&1
    n=$((n + 1))
  done
  printf '已休眠 %s 个后台应用\n' "$n"
}

do_doze() {
  [ -n "$2" ] || return 1
  case "$1" in
    add) dumpsys deviceidle whitelist +"$2" >/dev/null 2>&1 ;;
    del) dumpsys deviceidle whitelist -"$2" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
  printf 'OK\n'
}

case "$1" in
  list)
    do_list
    ;;
  set)
    do_set "$2" "$3"
    ;;
  optimize)
    do_optimize
    ;;
  restore)
    do_restore
    ;;
  hibernate)
    do_hibernate
    ;;
  doze)
    do_doze "$2" "$3"
    ;;
  wl-list)
    cat "$WL" 2>/dev/null
    ;;
  wl-add)
    [ -n "$2" ] || exit 1
    in_wl "$2" || printf '%s\n' "$2" >> "$WL"
    printf 'OK\n'
    ;;
  wl-del)
    [ -n "$2" ] || exit 1
    grep -vxF "$2" "$WL" > "$WL.t" 2>/dev/null
    mv -f "$WL.t" "$WL" 2>/dev/null
    printf 'OK\n'
    ;;
  *)
    printf 'usage: appctl.sh {list|set <pkg> <level>|optimize|restore|hibernate|doze <add|del> <pkg>|wl-add|wl-del|wl-list}\n'
    ;;
esac