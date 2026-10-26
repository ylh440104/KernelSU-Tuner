#!/system/bin/sh

CFG_DIR=/data/adb/ksu_tuner
CFG=$CFG_DIR/config.conf
CFG_VER=2

cfg_lock_wait() {
  i=0
  while [ "$i" -lt 15 ]; do
    mkdir "$CFG_DIR/.lock" 2>/dev/null && return 0
    j=0
    while [ "$j" -lt 10 ]; do
      sleep 1
      j=$((j + 1))
    done
    i=$((i + 1))
  done
  return 0
}

cfg_unlock() {
  rmdir "$CFG_DIR/.lock" 2>/dev/null
  return 0
}

cfg_read() {
  [ -f "$CFG" ] || return 1
  sed -n "s/^$1=//p" "$CFG" 2>/dev/null | tail -n 1
}

cfg_write() {
  [ -f "$CFG" ] || : > "$CFG"
  tmp="$CFG_DIR/.cfg.$$"
  awk -v k="$1" -v v="$2" '
    BEGIN { done = 0 }
    $0 ~ "^" k "=" { if (!done) { print k "=" v; done = 1 } ; next }
    { print }
    END { if (!done) print k "=" v }
  ' "$CFG" > "$tmp" 2>/dev/null || return 1
  [ -s "$tmp" ] || { rm -f "$tmp" 2>/dev/null; return 1; }
  chmod 600 "$tmp" 2>/dev/null
  mv -f "$tmp" "$CFG" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  return 0
}

cfg_version() {
  v=$(cfg_read SCHEMA)
  case "$v" in ''|*[!0-9]*) printf '1' ;; *) printf '%s' "$v" ;; esac
}

cfg_migrate() {
  [ -f "$CFG" ] || return 0
  cur=$(cfg_version)
  [ "$cur" -ge "$CFG_VER" ] && return 0
  cfg_lock_wait
  if [ "$cur" -lt 2 ]; then
    for kv in "CPU_FREQ=1" "LMK_TUNE=1" "ZRAM_SIZE=0" "THERMAL_ZONES=cpu,gpu" \
              "AUTO_LOWPOWER=1" "AUTO_WINDOW_ON=0" "AUTO_WINDOW=2300-0700" \
              "AUTO_WINDOW_PROFILE=powersave" "SAFEGUARD=1" "GUARD_MODE=3" \
              "GUARD_PATTERN=1" "GUARD_ANSWER=pending" "DEVFREQ=0" "KSM=0" \
              "THP=0" "SCHEDTUNE=0" "TCP_TUNE=0" "BOOST=0" "BATT_PROFILE=0" \
              "BATT_LOW=20" "WATCHDOG=1" "FS_TUNE=0"; do
      k=${kv%%=*}
      have=$(cfg_read "$k")
      [ -n "$have" ] || cfg_write "$k" "${kv#*=}"
    done
  fi
  cfg_write SCHEMA "$CFG_VER"
  cfg_unlock
  return 0
}

cfg_boot_ok() {
  printf '%s\n' "0" > "$CFG_DIR/bootfail" 2>/dev/null
  chmod 600 "$CFG_DIR/bootfail" 2>/dev/null
  return 0
}

cfg_boot_fail_count() {
  n=0
  [ -f "$CFG_DIR/bootfail" ] && n=$(head -n 1 "$CFG_DIR/bootfail" 2>/dev/null)
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s' "$n"
}

cfg_boot_inc() {
  n=$(cfg_boot_fail_count)
  n=$((n + 1))
  printf '%s\n' "$n" > "$CFG_DIR/bootfail" 2>/dev/null
  chmod 600 "$CFG_DIR/bootfail" 2>/dev/null
  printf '%s' "$n"
}

case "$1" in
  read)
    cfg_read "$2"
    printf '\n'
    ;;
  write)
    cfg_write "$2" "$3" && printf 'OK\n'
    ;;
  migrate)
    cfg_migrate && printf 'OK schema=%s\n' "$(cfg_version)"
    ;;
  version)
    cfg_version
    printf '\n'
    ;;
  boot-inc)
    cfg_boot_inc
    printf '\n'
    ;;
  boot-ok)
    cfg_boot_ok
    printf 'OK\n'
    ;;
  boot-count)
    cfg_boot_fail_count
    printf '\n'
    ;;
  *)
    printf 'usage: cfg.sh {read K|write K V|migrate|version|boot-inc|boot-ok|boot-count}\n'
    ;;
esac
