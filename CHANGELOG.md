# 更新日志

版本号与 `module.prop` 中的 `version` 一致，括号内为 `versionCode`。

## v3.4.2 (30042)

作者字段改为 ylh440104。

- `module.prop` 的 `author` 与 `module.yaml` 保持一致。

## v3.4.1 (30041)

修复 WebUI 无法加载。

- 修复 `webroot/index.html` 里的语法错误：一段字符串字面量被换行拆成了三行，导致整个 script 解析失败，WebUI 完全打不开。
- 清理真正的重复代码：`CPU_FREQ` 开关行、`zoneRow` 行、以及「内核扩展调优」和「守护进程」两张卡片及其脚本块各多出一份。
- 补回上一版误删的两处：`p-live` 面板的开标签，以及「变更预览」卡片（脚本仍在引用其中的 `drRun` 按钮）。

## v3.4.0 (30040)

内核扩展调优、配置版本化、SELinux 规则、看门狗。

- 新增 `bin/kernel.sh`，覆盖之前没碰过的几块：
  - devfreq 总线与内存控制器调频，四档各配一套 governor
  - KSM 内存去重、THP 透明大页、`vm.page-cluster`
  - schedtune 的 boost、prefer_idle 和 uclamp.min
  - TCP 三层缓冲 `tcp_rmem` / `tcp_wmem`、`netdev_max_backlog`、`netdev_budget`
  - 触控 boost（cpu_boost、msm_performance、cpu_input_boost）
  - 文件系统上限 inotify / file-max / nr_open / protected_*
- 新增 `bin/watchdog.sh`：周期性检查四个守护进程，掉线自动拉起。
- 新增 `bin/cfg.sh`：配置读写统一走原子替换，并带 SCHEMA 版本号与自动迁移。
- 新增 `sepolicy.rule`：为 init 补齐写入 sysfs / procfs / devfreq / cgroup 等节点所需的 SELinux 规则。
- 新增定时 TRIM（`TRIM_INTERVAL`，单位天）与低电量自动切省电（`BATT_PROFILE` / `BATT_LOW`）。
- 修复：安全模式触发时用追加方式写 `SAFEGUARD=0`，会在配置里产生重复键。
- 修复：`bootfail` 计数器清空后留下空文件，改为统一写 `0`。
- WebUI 工具页增加内核扩展开关组、看门狗控制和 devfreq 查看。

## v3.2.0 (30020)

配置备份、CPU 频率上下限、LMK 与 ZRAM 调优。

- 新增 `bin/backup.sh`：把选项、per-app 规则、自定义参数、白名单导出为一个 JSON 文件；导入时按 key 合并，不在备份里的配置保持不变。
- 预设现在会写 `scaling_max_freq` / `scaling_min_freq`，取值从内核实际支持的频率表里挑最接近的一档。省电 10-45%，均衡 20-75%，性能 45-92%，游戏 60-100%。
- `custom.sh` 写入前会读节点旁边的 min/max（也支持 `节点名_max` 这种命名），超范围直接拒绝，可用 `force` 绕过。
- 新增 LMK 调优：`min_free_kbytes` 按内存容量分档，`lowmemorykiller/minfree` 按预设设置，另调 `watermark_scale_factor` 与 `watermark_boost_factor`。
- 新增 ZRAM 大小设置：zram0 尚无大小时按内存 75% 分配，限制在 256MB 到 8GB 之间，随后 mkswap 与 swapon。已有大小不动。
- 温控解锁不再一刀切关掉所有 zone，改由 `THERMAL_ZONES` 选择，默认 `cpu,gpu`。新增 `tuner.sh zones` 列出所有温控区。
- 智能驾驶支持系统省电模式联动，以及按时间段强制预设，跨天区间可用。
- WebUI 增加对应开关、温控区选择器和时间段输入。

## v3.1.0 (30010)

CPU 频率上下限、防砖回滚、防格机防护。

- 新增 CPU 频率上下限控制（`freq_pick()` 按百分比从可用频率表取最接近值）。
- 新增防砖机制：`post-fs-data.sh` 累加启动计数，`boot-completed.sh` 成功后清零，连续三次失败自动回滚并写入 `disable`。
- 新增 `bin/wipeshield.sh`，三种模式监控格机类操作：增强模式检测到即终止，普通模式先询问，不防护只记日志。
- `module.prop` 增加 `updateJson`，管理器可提示更新。
- WebUI 增加防护页，共 8 个标签。

## v3.0.3 (30003)

模块 ID 对齐注册记录。

- `module.prop` 与 `module.yaml` 的 id 统一为 `KernelSU-Tuner`，与 KernelSU Modules 的注册 ID 一致。
- 同步修改模块安装路径、initrc 文件名与服务名。
- 运行时数据目录 `/data/adb/ksu_tuner` 保持不变，避免已安装用户丢配置。

## v3.0.2 (30002)

修复发布流程。

- 补齐 `module.yaml`，通过官方 JSON Schema 校验。
- 增加模块图标。
- 启用 release immutability。
- 修复上传时未带 `base_tree` 导致仓库文件被覆盖的问题。

## v3.0.0 (30000)

四功能整合版。

- 新增 `bin/appwatch.sh`：按前台应用自动切换预设，前台包名识别带三级回退链。
- 新增 `bin/custom.sh`：任意 `/sys` `/proc` 节点读写，带路径白名单与按项还原。
- 新增 `initrc/KernelSU-Tuner.rc`：init 常驻服务，比 `service.sh` 启动更早。
- 新增 `bin/display.sh`：刷新率与触控采样率调节。
- 动作按钮升级为六态循环，WebUI 扩展为七个标签。

## v2.0.0 (20000)

三大守护子系统。

- 新增 `bin/autopilot.sh`：读取温度、息屏、充电状态自动切换预设，带冷却滞回状态机。
- 新增 `bin/guard.sh`：充电上限保护，自适应五类控制节点。
- 新增 `bin/appctl.sh`：应用待机管理，Standby Bucket 分档与白名单。
- 新增 GPU 调频与 DNS 优化。
- 引入 `KSU_SYS` 环境变量注入点，便于不刷机测试。
- WebUI 升级为五个标签。

## v1.0.0 (10000)

首个版本。

- 核心引擎 `bin/tuner.sh`，支持 apply / fast / monitor / revert / status / set / get / list / trim / log 等子命令。
- 四档预设：省电、均衡、性能、游戏。
- 覆盖 CPU 调度器、IO 调度器、预读、VM、网络、ZRAM 压缩、温控、printk、SELinux、IPv6、动画缩放、TRIM、日志抓取。
- 所有写入前先备份原值，设备不支持则跳过。
- 单文件 WebUI。
