# KernelSU Tuner

A KernelSU module that tunes kernel parameters on rooted Android and keeps
track of what it changed, so you can put everything back.

Everything here is reversible. Before any write the previous value is saved
to `/data/adb/ksu_tuner/backup.conf`, and if a node does not exist on your
device the module simply skips it. Nothing is hardcoded for a specific SoC.

---

## What it does

Four profiles: `powersave`, `balanced`, `performance`, `gaming`. Each one
adjusts the parameters your kernel actually exposes.

**CPU**
- governor selection, checked against `scaling_available_governors`
- frequency floor and ceiling, snapped to values from
  `scaling_available_frequencies`
- optional core pinning

**GPU**
- Adreno and Mali frequency levels plus their governor, when the paths exist

**Storage**
- IO scheduler per device class, read-ahead and queue depth
- boot-time fstrim

**Memory**
- swappiness, dirty page ratios, cache pressure, overcommit
- lowmemorykiller minfree and `min_free_kbytes`, scaled by installed RAM
- watermark tuning
- zram compression algorithm, and zram sizing when the device has none yet

**Network**
- congestion control (BBR preferred, falls back to cubic/westwood/reno)
- socket buffer sizes, TCP Fast Open, timeout tuning
- optional encrypted DNS per profile

**Display**
- refresh rate and touch sampling rate, read from the panel's own list of
  supported modes

**Thermal**
- per-zone unlock. You pick which zones to release, cpu and gpu by default,
  rather than disabling every sensor on the device.

---

## Background behaviour

Three daemons, all off by default, each with a pid file, a stop path that
restores what it changed, and a log capped at 200 lines.

**AutoPilot** watches temperature, screen state and charging, and switches
profiles on its own. It has a hysteresis state machine so it does not
thermal-thrash, and it can also follow the system battery saver or force a
profile during a time window (windows crossing midnight work).

**BatteryGuard** caps charging at a level you choose, adapting to whichever
of the five common control interfaces your device uses.

**AppWatch** follows the foreground app and applies a per-app profile. The
foreground package is resolved through a three-level fallback chain so it
works across Android versions and multi-user setups.

---

## Wipe protection

A separate guard watches running processes and boot scripts for destructive
commands: `rm -rf` against system paths, `mkfs`, `dd` to block devices,
`fastboot erase/format/-w`, `shred`. Temporary locations such as `/tmp`,
`/cache` and `/data/local/tmp` are deliberately left alone so ordinary
tooling keeps working.

Three modes:

| Mode | Behaviour |
|---|---|
| 增强 (strict) | kills the process the moment a match is found |
| 普通 (normal) | pauses and asks you, through the WebUI |
| 不防护 (off) | logs only |

This is one layer of defence, not a guarantee. It cannot see inside a
binary, and it cannot stop something already running in kernel space. The
real protection is only installing modules you trust.

---

## Boot-failure rollback

The module counts boots. `post-fs-data.sh` increments the counter,
`boot-completed.sh` clears it once the system is up. Three consecutive
failures trigger a rollback of every kernel and custom parameter, then the
module writes its own `disable` flag and turns the safeguard off. If a
custom parameter turns out to be wrong, this is what gets you back.

---

## Custom parameters

You can write any `/sys` or `/proc` node. Before writing, the module reads
the `min` and `max` files next to the target (it also handles the
`node_max` / `node_min` naming convention) and refuses values outside that
range. Pass `force` if you know better.

Per-app parameters go further: a node and value are tied to a package, and
applied only while that package is in the foreground. Handy for capping one
game's clock without slowing everything else.

---

## WebUI

Nine tabs: profiles, advanced switches, autopilot, battery, per-app rules,
app management, display, wipe protection, and a tools tab for backup,
custom presets, per-app parameters and a dry-run preview.

The dry-run lists exactly which nodes a profile would change and from what
to what, without writing anything.

---

## Backup

Everything you configure exports to a single JSON file under
`/sdcard/KernelSU-Tuner-Backup`. Importing merges keys rather than
replacing the file, so settings that are not in the backup are preserved.

---

## Command line

```
bin/tuner.sh     apply|fast|dry|monitor|revert|status|set|get|list|trim|log|zones
bin/autopilot.sh start|stop|status|once
bin/guard.sh     start|stop|status|node
bin/appctl.sh    list|set|optimize|restore|hibernate|doze|wl-add|wl-del|wl-list
bin/appwatch.sh  start|stop|status|fg|once|rules|set|del
bin/custom.sh    list|check|add|del|set|read|apply|revert
                 app-list|app-add|app-del|app-apply|app-revert
bin/display.sh   status|refresh|touch|apply|nodes
bin/wipeshield.sh start|stop|status|mode|answer|signal|test|log
bin/backup.sh    export|import|list|path
bin/presets.sh   list|save|del|apply
```

---

## Requirements

- KernelSU with module support
- Android 8 or newer
- A kernel that exposes the nodes you want to change. Anything missing is
  skipped, so a partial setup is normal.

---

## Notes

Thermal unlock and SELinux permissive both reduce the protection your
device ships with. They are off by default and worth leaving that way
unless you have a specific reason.

Zram resizing needs a reboot to take effect, and some kernels do not allow
reconfiguring zram once swap is active. It is off by default.

---

## License

GPL-3.0-only. See `LICENSE`.
