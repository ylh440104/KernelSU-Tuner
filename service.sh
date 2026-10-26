#!/system/bin/sh

MODDIR=${0%/*}
CFG_DIR=/data/adb/ksu_tuner
CFG=$CFG_DIR/config.conf

mkdir -p "$CFG_DIR" 2>/dev/null
[ -f "$CFG" ] || exit 0

get() {
  sed -n "s/^$1=//p" "$CFG" 2>/dev/null | tail -n 1
}

profile=$(get PROFILE)
[ -n "$profile" ] || profile=balanced

sh "$MODDIR/bin/tuner.sh" apply "$profile"

if [ "$(get AUTOPILOT)" = "1" ]; then
  sh "$MODDIR/bin/autopilot.sh" start >/dev/null 2>&1
fi

if [ "$(get BATT_GUARD)" = "1" ]; then
  sh "$MODDIR/bin/guard.sh" start >/dev/null 2>&1
fi

if [ "$(get APPWATCH)" = "1" ]; then
  sh "$MODDIR/bin/appwatch.sh" start >/dev/null 2>&1
fi

if [ "$(get DISP_TUNE)" = "1" ]; then
  sh "$MODDIR/bin/display.sh" apply "$profile" >/dev/null 2>&1
fi

gm=$(get GUARD_MODE)
[ -n "$gm" ] || gm=3
if [ "$gm" != "3" ]; then
  sh "$MODDIR/bin/wipeshield.sh" start >/dev/null 2>&1
fi

if [ -s "$CFG_DIR/custom.conf" ]; then
  sh "$MODDIR/bin/custom.sh" apply >/dev/null 2>&1
fi

if [ "$(get WATCHDOG)" = "1" ]; then
  sh "$MODDIR/bin/watchdog.sh" start >/dev/null 2>&1
fi
if [ "$(get LOG_CAPTURE)" = "1" ]; then
  mkdir -p "$CFG_DIR/logs" 2>/dev/null
  (
    sleep 20
    dmesg > "$CFG_DIR/logs/dmesg-$(date +%Y%m%d-%H%M%S).log" 2>/dev/null
    ls -t "$CFG_DIR/logs"/dmesg-*.log 2>/dev/null | tail -n +6 | while read -r f; do
      rm -f "$f" 2>/dev/null
    done
  ) &
fi