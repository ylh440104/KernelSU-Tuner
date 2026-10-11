#!/system/bin/sh

CFG_DIR=/data/adb/ksu_tuner
CFG=$CFG_DIR/config.conf
BAK=$CFG_DIR/backup.conf

MODDIR=${0%/*}

for d in autopilot guard appwatch shield; do
  if [ -f "$CFG_DIR/$d.pid" ]; then
    p=$(cat "$CFG_DIR/$d.pid" 2>/dev/null)
    [ -n "$p" ] && kill "$p" 2>/dev/null
    rm -f "$CFG_DIR/$d.pid"
  fi
done

if [ -x "$MODDIR/bin/appctl.sh" ]; then
  sh "$MODDIR/bin/appctl.sh" restore >/dev/null 2>&1
fi

if [ -x "$MODDIR/bin/custom.sh" ]; then
  sh "$MODDIR/bin/custom.sh" revert >/dev/null 2>&1
fi

if [ -x "$MODDIR/bin/display.sh" ]; then
  sh "$MODDIR/bin/display.sh" refresh balanced >/dev/null 2>&1
  sh "$MODDIR/bin/display.sh" touch balanced >/dev/null 2>&1
fi

if [ -s "$BAK" ]; then
  while IFS='|' read -r p v; do
    [ -n "$p" ] || continue
    [ -f "$p" ] || continue
    chmod 0644 "$p" 2>/dev/null
    ( printf '%s' "$v" > "$p" ) 2>/dev/null
  done < "$BAK"
fi

if command -v settings >/dev/null 2>&1; then
  settings delete global window_animation_scale 2>/dev/null
  settings delete global transition_animation_scale 2>/dev/null
  settings delete global animator_duration_scale 2>/dev/null
fi

for d in /proc/sys/net/ipv6/conf/*/disable_ipv6; do
  [ -f "$d" ] || continue
  printf '0' > "$d" 2>/dev/null
done

rm -rf "$CFG_DIR" 2>/dev/null