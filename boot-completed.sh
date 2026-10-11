#!/system/bin/sh

MODDIR=${0%/*}
CFG_DIR=/data/adb/ksu_tuner
CFG=$CFG_DIR/config.conf

[ -f "$CFG" ] || exit 0

: > "$CFG_DIR/bootfail"
chmod 600 "$CFG_DIR/bootfail" 2>/dev/null

if [ -f "$MODDIR/disable" ]; then
  printf '%s\n' "safe mode was triggered, module left disabled" >> "$CFG_DIR/tuner.log"
  exit 0
fi

get() {
  sed -n "s/^$1=//p" "$CFG" 2>/dev/null | tail -n 1
}

setkv() {
  sed -i "/^$1=/d" "$CFG" 2>/dev/null
  printf '%s=%s\n' "$1" "$2" >> "$CFG"
}

if [ "$(get ANIM_FAST)" = "1" ]; then
  settings put global window_animation_scale 0.5 2>/dev/null
  settings put global transition_animation_scale 0.5 2>/dev/null
  settings put global animator_duration_scale 0.5 2>/dev/null
fi

if [ "$(get FSTRIM_BOOT)" = "1" ]; then
  (
    sleep 60
    if command -v fstrim >/dev/null 2>&1; then
      out=$(fstrim -v /data 2>&1)
    else
      out=$(/system/bin/fstrim -v /data 2>&1)
    fi
    setkv LAST_TRIM "$(date '+%Y-%m-%d %H:%M:%S')"
    printf '%s FSTRIM: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$out" >> "$CFG_DIR/tuner.log"
  ) &
fi

prof=$(get PROFILE)
[ -n "$prof" ] || prof=balanced
desc="已启用 | 预设: $prof"
if [ "$(get THERMAL_OPEN)" = "1" ]; then
  desc="$desc | 温控已解锁"
fi
if [ "$(get SELINUX_PERM)" = "1" ]; then
  desc="$desc | SELinux 宽容"
fi
if [ "$(get SAFEGUARD)" = "1" ]; then
  desc="$desc | 防砖已开"
fi

if command -v ksud >/dev/null 2>&1; then
  ksud module config set override.description "$desc" 2>/dev/null
fi

printf '%s 启动完成，预设=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$prof" >> "$CFG_DIR/tuner.log"
