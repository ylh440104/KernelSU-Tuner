#!/system/bin/sh

MODDIR=${0%/*}
CFG_DIR=/data/adb/ksu_tuner
CFG=$CFG_DIR/config.conf

mkdir -p "$CFG_DIR" 2>/dev/null
chmod 700 "$CFG_DIR" 2>/dev/null

if [ -f "$CFG" ]; then
  chmod 600 "$CFG" 2>/dev/null
else
  printf 'PROFILE=balanced\nCPU_GOV=1\nCPU_PIN=0\nIO_SCHED=1\nREAD_AHEAD=1\nVM_TUNE=1\nNET_TUNE=1\nZRAM_TUNE=1\nPRINTK_OFF=0\nTHERMAL_OPEN=0\nSELINUX_PERM=0\nIPV6_OFF=0\nANIM_FAST=0\nFSTRIM_BOOT=1\nLOG_CAPTURE=1\nGPU_TUNE=1\nDNS_TUNE=0\nAUTOPILOT=0\nAUTO_BASE=balanced\nAUTO_COOL=powersave\nAUTO_TEMP_HIGH=45000\nAUTO_TEMP_LOW=40000\nAUTO_SCREEN=1\nAUTO_CHARGE=0\nBATT_GUARD=0\nCHARGE_LIMIT=80\nDISP_TUNE=0\nDISP_HZ=-\nDISP_TOUCH=-\nAPPWATCH=0\nWATCH_BASE=balanced\nLAST_APPLY=-\nLAST_TRIM=-\n' > "$CFG"
  chmod 600 "$CFG" 2>/dev/null
fi

[ -f "$CFG_DIR/backup.conf" ] || : > "$CFG_DIR/backup.conf"
chmod 600 "$CFG_DIR/backup.conf" 2>/dev/null
[ -f "$CFG_DIR/tuner.log" ] || : > "$CFG_DIR/tuner.log"
chmod 600 "$CFG_DIR/tuner.log" 2>/dev/null

if [ "$KSU_LATE_LOAD" = "1" ]; then
  printf 'late-load mode\n' >> "$CFG_DIR/tuner.log"
fi