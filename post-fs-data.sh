#!/system/bin/sh

MODDIR=${0%/*}
CFG_DIR=/data/adb/ksu_tuner
CFG=$CFG_DIR/config.conf
BOOTLOG=$CFG_DIR/bootfail

mkdir -p "$CFG_DIR" 2>/dev/null
chmod 700 "$CFG_DIR" 2>/dev/null

if [ -f "$CFG" ]; then
  chmod 600 "$CFG" 2>/dev/null
else
  printf 'PROFILE=balanced\nCPU_GOV=1\nCPU_FREQ=1\nCPU_PIN=0\nIO_SCHED=1\nREAD_AHEAD=1\nVM_TUNE=1\nNET_TUNE=1\nZRAM_TUNE=1\nLMK_TUNE=1\nZRAM_SIZE=0\nTHERMAL_ZONES=cpu,gpu\nPRINTK_OFF=0\nTHERMAL_OPEN=0\nSELINUX_PERM=0\nIPV6_OFF=0\nANIM_FAST=0\nFSTRIM_BOOT=1\nLOG_CAPTURE=1\nGPU_TUNE=1\nDNS_TUNE=0\nAUTOPILOT=0\nAUTO_BASE=balanced\nAUTO_COOL=powersave\nAUTO_TEMP_HIGH=45000\nAUTO_TEMP_LOW=40000\nAUTO_SCREEN=1\nAUTO_CHARGE=0\nAUTO_LOWPOWER=1\nAUTO_WINDOW_ON=0\nAUTO_WINDOW=2300-0700\nAUTO_WINDOW_PROFILE=powersave\nBATT_GUARD=0\nCHARGE_LIMIT=80\nDISP_TUNE=0\nDISP_HZ=-\nDISP_TOUCH=-\nAPPWATCH=0\nWATCH_BASE=balanced\nSAFEGUARD=1\nGUARD_MODE=3\nGUARD_PATTERN=1\nLAST_APPLY=-\nLAST_TRIM=-\nSCHEMA=2\nDEVFREQ=0\nKSM=0\nTHP=0\nSCHEDTUNE=0\nTCP_TUNE=0\nBOOST=0\nFS_TUNE=0\nBATT_PROFILE=0\nBATT_LOW=20\nWATCHDOG=1\nTRIM_INTERVAL=0\nGUARD_ANSWER=pending\n' > "$CFG"
  chmod 600 "$CFG" 2>/dev/null
fi

[ -f "$CFG_DIR/backup.conf" ] || : > "$CFG_DIR/backup.conf"
chmod 600 "$CFG_DIR/backup.conf" 2>/dev/null
[ -f "$CFG_DIR/tuner.log" ] || : > "$CFG_DIR/tuner.log"
chmod 600 "$CFG_DIR/tuner.log" 2>/dev/null

if [ "$KSU_LATE_LOAD" = "1" ]; then
  printf 'late-load mode\n' >> "$CFG_DIR/tuner.log"
fi

if [ -x "$MODDIR/bin/cfg.sh" ]; then
  . "$MODDIR/bin/cfg.sh"
  CFG_DIR=/data/adb/ksu_tuner
  CFG=$CFG_DIR/config.conf
  cfg_migrate >/dev/null 2>&1
fi
n=0
[ -f "$BOOTLOG" ] && n=$(head -n 1 "$BOOTLOG" 2>/dev/null)
case "$n" in ''|*[!0-9]*) n=0 ;; esac
n=$((n + 1))
printf '%s\n' "$n" > "$BOOTLOG"
chmod 600 "$BOOTLOG" 2>/dev/null

setkv() {
  tmp="$CFG_DIR/.cfg.$$"
  awk -v k="$1" -v v="$2" '
    BEGIN { done = 0 }
    $0 ~ "^" k "=" { if (!done) { print k "=" v; done = 1 } ; next }
    { print }
    END { if (!done) print k "=" v }
  ' "$CFG" > "$tmp" 2>/dev/null || return 1
  [ -s "$tmp" ] || { rm -f "$tmp" 2>/dev/null; return 1; }
  chmod 600 "$tmp" 2>/dev/null
  mv -f "$tmp" "$CFG" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  return 0
}
sg=$(sed -n 's/^SAFEGUARD=//p' "$CFG" 2>/dev/null | tail -n 1)
[ -n "$sg" ] || sg=1
if [ "$sg" = "1" ] && [ "$n" -ge 3 ]; then
  sh "$MODDIR/bin/tuner.sh" revert >/dev/null 2>&1
  sh "$MODDIR/bin/custom.sh" revert >/dev/null 2>&1
  printf '%s\n' "0" > "$CFG_DIR/bootfail"
  chmod 600 "$CFG_DIR/bootfail" 2>/dev/null
  printf '%s\n' "safe mode triggered after $n failed boots" >> "$CFG_DIR/tuner.log"
  if [ ! -f "$MODDIR/disable" ]; then
    : > "$MODDIR/disable"
  fi
  setkv SAFEGUARD 0
  setkv LAST_APPLY -
  setkv SCHEMA 2
  exit 0
fi
