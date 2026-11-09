#!/system/bin/sh

MODDIR=$(cd "${0%/*}" 2>/dev/null && cd .. && pwd)
[ -n "$MODDIR" ] || MODDIR=/data/adb/modules/KernelSU-Tuner

CFG_DIR=/data/adb/ksu_tuner
CFG=$CFG_DIR/config.conf

[ -f "$CFG" ] || exit 0

get() {
  sed -n "s/^$1=//p" "$CFG" 2>/dev/null | tail -n 1
}

prof=$(get PROFILE)
[ -n "$prof" ] || prof=balanced
case "$prof" in
  powersave|balanced|performance|gaming) ;;
  *) prof=balanced ;;
esac
bootid=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
mark="$CFG_DIR/.applied.$bootid"
[ -n "$bootid" ] && [ -f "$mark" ] && exit 0
sh "$MODDIR/bin/tuner.sh" apply "$prof" >/dev/null 2>&1
[ -n "$bootid" ] && : > "$mark" 2>/dev/null
printf '%s initrc 服务已应用预设 %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$prof" >> "$CFG_DIR/tuner.log" 2>/dev/null

exit 0