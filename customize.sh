ui_print " "
ui_print "**********************************"
ui_print "  KernelSU Tuner  $MODNAME"
ui_print "  版本: $MODVER"
ui_print "  架构: $ARCH    API: $API"
ui_print "**********************************"
ui_print " "

mkdir -p /data/adb/ksu_tuner
chmod 700 /data/adb/ksu_tuner

if [ ! -f /data/adb/ksu_tuner/config.conf ]; then
  printf 'PROFILE=balanced\n' > /data/adb/ksu_tuner/config.conf
  printf 'CPU_GOV=1\n' >> /data/adb/ksu_tuner/config.conf
  printf 'CPU_PIN=0\n' >> /data/adb/ksu_tuner/config.conf
  printf 'CPU_FREQ=1\n' >> /data/adb/ksu_tuner/config.conf
  printf 'IO_SCHED=1\n' >> /data/adb/ksu_tuner/config.conf
  printf 'READ_AHEAD=1\n' >> /data/adb/ksu_tuner/config.conf
  printf 'VM_TUNE=1\n' >> /data/adb/ksu_tuner/config.conf
  printf 'NET_TUNE=1\n' >> /data/adb/ksu_tuner/config.conf
  printf 'ZRAM_TUNE=1\n' >> /data/adb/ksu_tuner/config.conf
  printf 'LMK_TUNE=1\n' >> /data/adb/ksu_tuner/config.conf
  printf 'ZRAM_SIZE=0\n' >> /data/adb/ksu_tuner/config.conf
  printf 'THERMAL_ZONES=cpu,gpu\n' >> /data/adb/ksu_tuner/config.conf
  printf 'PRINTK_OFF=0\n' >> /data/adb/ksu_tuner/config.conf
  printf 'THERMAL_OPEN=0\n' >> /data/adb/ksu_tuner/config.conf
  printf 'SELINUX_PERM=0\n' >> /data/adb/ksu_tuner/config.conf
  printf 'IPV6_OFF=0\n' >> /data/adb/ksu_tuner/config.conf
  printf 'ANIM_FAST=0\n' >> /data/adb/ksu_tuner/config.conf
  printf 'FSTRIM_BOOT=1\n' >> /data/adb/ksu_tuner/config.conf
  printf 'LOG_CAPTURE=1\n' >> /data/adb/ksu_tuner/config.conf
  printf 'GPU_TUNE=1\n' >> /data/adb/ksu_tuner/config.conf
  printf 'DNS_TUNE=0\n' >> /data/adb/ksu_tuner/config.conf
  printf 'AUTOPILOT=0\n' >> /data/adb/ksu_tuner/config.conf
  printf 'AUTO_BASE=balanced\n' >> /data/adb/ksu_tuner/config.conf
  printf 'AUTO_COOL=powersave\n' >> /data/adb/ksu_tuner/config.conf
  printf 'AUTO_TEMP_HIGH=45000\n' >> /data/adb/ksu_tuner/config.conf
  printf 'AUTO_TEMP_LOW=40000\n' >> /data/adb/ksu_tuner/config.conf
  printf 'AUTO_SCREEN=1\n' >> /data/adb/ksu_tuner/config.conf
  printf 'AUTO_CHARGE=0\n' >> /data/adb/ksu_tuner/config.conf
  printf 'AUTO_LOWPOWER=1\n' >> /data/adb/ksu_tuner/config.conf
  printf 'AUTO_WINDOW_ON=0\n' >> /data/adb/ksu_tuner/config.conf
  printf 'AUTO_WINDOW=2300-0700\n' >> /data/adb/ksu_tuner/config.conf
  printf 'AUTO_WINDOW_PROFILE=powersave\n' >> /data/adb/ksu_tuner/config.conf
  printf 'BATT_GUARD=0\n' >> /data/adb/ksu_tuner/config.conf
  printf 'CHARGE_LIMIT=80\n' >> /data/adb/ksu_tuner/config.conf
  printf 'DISP_TUNE=0\n' >> /data/adb/ksu_tuner/config.conf
  printf 'DISP_HZ=-\n' >> /data/adb/ksu_tuner/config.conf
  printf 'DISP_TOUCH=-\n' >> /data/adb/ksu_tuner/config.conf
  printf 'APPWATCH=0\n' >> /data/adb/ksu_tuner/config.conf
  printf 'WATCH_BASE=balanced\n' >> /data/adb/ksu_tuner/config.conf
  printf 'SAFEGUARD=1\n' >> /data/adb/ksu_tuner/config.conf
  printf 'GUARD_MODE=3\n' >> /data/adb/ksu_tuner/config.conf
  printf 'GUARD_PATTERN=1\n' >> /data/adb/ksu_tuner/config.conf
  printf 'GUARD_ANSWER=pending\n' >> /data/adb/ksu_tuner/config.conf
  printf 'LAST_APPLY=-\n' >> /data/adb/ksu_tuner/config.conf
  printf 'LAST_TRIM=-\n' >> /data/adb/ksu_tuner/config.conf
  chmod 600 /data/adb/ksu_tuner/config.conf
  ui_print "- 已写入默认配置"
else
  ui_print "- 保留已有配置"
fi

rm -f /data/adb/ksu_tuner/backup.conf
: > /data/adb/ksu_tuner/backup.conf
chmod 600 /data/adb/ksu_tuner/backup.conf

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/bin/tuner.sh" 0 0 0755
set_perm "$MODPATH/bin/autopilot.sh" 0 0 0755
set_perm "$MODPATH/bin/guard.sh" 0 0 0755
set_perm "$MODPATH/bin/appctl.sh" 0 0 0755
set_perm "$MODPATH/bin/appwatch.sh" 0 0 0755
set_perm "$MODPATH/bin/custom.sh" 0 0 0755
set_perm "$MODPATH/bin/display.sh" 0 0 0755
set_perm "$MODPATH/bin/wipeshield.sh" 0 0 0755
set_perm "$MODPATH/bin/backup.sh" 0 0 0755
set_perm "$MODPATH/bin/presets.sh" 0 0 0755
set_perm "$MODPATH/bin/kernel.sh" 0 0 0755
set_perm "$MODPATH/bin/watchdog.sh" 0 0 0755
set_perm "$MODPATH/bin/cfg.sh" 0 0 0755
set_perm "$MODPATH/bin/init-apply.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/boot-completed.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/customize.sh" 0 0 0755

ui_print "- 权限与目录已就绪"
ui_print "- 重启后生效，可在模块 WebUI 中调整"
ui_print " "
