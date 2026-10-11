# KernelSU Tuner

给 KernelSU 写的一个调优模块。主要想解决两件事：把散在各个 `sysfs` / `proc` 节点的性能参数集中管起来，以及让这些参数能根据实际情况自己切换。

起因是之前用过的那些"性能优化"脚本，改完之后想还原只能重刷，而且很多脚本不看机型，往同一个值上怼。所以这个模块从第一天起就定了两条规矩：**写入前必须备份原值**，**设备不支持就跳过而不是报错**。

代码全是 shell 和原生 JS，没有依赖任何第三方东西，装完断网也能用。

---

## 环境要求

| 项目 | 要求 |
|---|---|
| KernelSU | v0.9.0 以上（用到 `ksud module config` 和 initrc 注入） |
| Android | 10 以上 |
| 内核 | 4.14+，我用 5.10 GKI 实测 |
| 架构 | arm64-v8a / x86_64 都行，脚本层没有架构相关代码 |

没在 Magisk 上测过。Magisk 应该也能跑大部分功能，但 `ksud` 相关的那部分（动态模块描述）会直接失效。

---

## 它到底做了什么

### 四档预设

`powersave` / `balanced` / `performance` / `gaming`，切档会连带改动下面这些：

- **CPU 调度器** —— 从设备实际支持的 governor 列表里挑，不是硬写 `performance`。有的内核只有 `walt` 和 `schedutil`，那就挑得出来的那个。
- **GPU 调频** —— 高通走 `kgsl-3d0`，读 `num_pwrlevels` 算功率档位；Mali 和通用 devfreq 走 `available_governors`。两条路径都试，能中哪条算哪条。
- **IO 调度器 + 预读** —— `read_ahead_kb` 和 `nr_requests` 一起调，只改调度器其实意义不大。
- **VM 内存** —— swappiness、脏页回写比例、vfs_cache_pressure。
- **网络** —— 优先开 BBR，开不了就退到 cubic；收发缓冲区、TCP Fast Open、`tcp_tw_reuse` 一并设。
- **DNS** —— 按档位切，性能档会开加密 DNS（DoT）。
- **ZRAM 压缩算法** —— 优先 `zstd`，其次 `lz4`。已经在用的 swap 设备会跳过，不动它。

### 智能驾驶 AutoPilot

一个常驻循环，5 秒一轮，读温度 / 息屏状态 / 充电状态，决定该用哪一档。

```
温度 >= 阈值        -> 降温档
温度在降但没到位     -> 继续降温档（滞回）
屏幕关闭            -> 省电档
充电中（可选）       -> 性能档
其他                -> 基准档
```

**滞回这块是必须的**。最早我写的是"过热后强制降温 30 秒"，结果温度卡在阈值附近时会反复切档，比不切还费电。现在改成状态机：只有温度掉回 `AUTO_TEMP_LOW` 以下才解除冷却。

温度取值会跳过 `thermal_zone` 里那些明显无关的传感器，优先看 type 里带 `cpu` / `soc` / `gpu` / `tsens` / `battery` / `skin` 的。有些设备 temp 单位是摄氏度而不是毫摄氏度，代码里判断了（小于 200 就当摄氏度处理）。

### 电池守护 BatteryGuard

充电到设定上限就断电，掉到「上限 - 3%」再恢复，来回循环。

控制节点会按顺序找这几个，找到哪个用哪个：

```
charging_enabled    input_suspend    batt_slate_mode
store_mode          charge_disable
```

高通的 `charging_enabled` 和 `charge_disable` 极性是反的，代码里分开处理了。如果这五个节点一个都没有，会直接告诉你不支持，而不是默默失败。

> 提示：上限设 80% 对循环寿命帮助最明显。设 100% 等于没开。

### 应用待机管理

直接操作 Android 的 App Standby Bucket，比"一刀切杀后台"温和很多。

档位循环：`active` → `working` → `frequent` → `rare` → `restricted`

可以给任意应用单独设档，也能加白名单让它不受批量操作影响。WebUI 里有搜索框，应用多了不至于翻半天。

### 应用性能策略 AppWatch

按**前台应用**自动切档。打开游戏进游戏档，切回桌面回基准档。

前台包名识别做了三级回退，因为不同 Android 版本 `dumpsys` 的输出差别很大：

```
dumpsys activity activities   (mResumedActivity / topResumedActivity)
  ↓ 没结果
dumpsys window                (mCurrentFocus / mFocusedApp)
  ↓ 没结果
dumpsys activity top          (ACTIVITY 行)
```

实测覆盖了 Android 11 ~ 14 的几种格式，包括多用户（`u10`）和包名带下划线数字的情况。

### 显示调优

- 刷新率：按档位写 `peak_refresh_rate` / `min_refresh_rate`，均衡档会把设置删掉交还给系统
- 触控采样率：扫描 9 类触控节点，游戏档拉到 300Hz

这块**不是所有机器都有节点**，没有就只调刷新率，不会报错。

### 自定义内核参数

最后加的功能，也是我觉得最实用的。填路径和值就行，模块负责备份原值。

```
/sys/module/xxx/parameters/yyy   ->  你想要的值
```

路径限 `/sys` 和 `/proc`，会拦 `..` 和 `|`。每次写入前记录原始值，还原时**只还原自己改过的那几项**，不会动别的模块留下的备份。

### initrc 常驻服务

用 KernelSU 的 initrc 注入，让 init 进程在 `late_start` 阶段直接拉起，比 `service.sh` 更早。

```rc
service ksu_tuner_boot   /system/bin/sh .../bin/init-apply.sh
service ksu_tuner_watch  /system/bin/sh .../bin/appwatch.sh run
on property:sys.boot_completed=1
    start ksu_tuner_watch
```

改完配置想立刻生效的话，跑一下 `ksud initrc refresh`，下次开机用新的。

> late-load 模式下 initrc 注入不可用（KernelSU 本身的限制），这种情况 `service.sh` 会兜底。

---

## 安装

1. KernelSU 管理器 → 模块 → 从本地安装 → 选 zip
2. 重启

WebUI 在模块列表里点进去就行，动作按钮会按 `省电切档 → 智能驾驶 → 电池守护 → 应用追踪 → 关闭全部` 循环。

---

## 命令行

不想开 WebUI 的话，脚本都能直接调。

```sh
# 主控
sh /data/adb/modules/ksu_tuner/bin/tuner.sh status      # 看当前所有状态
sh /data/adb/modules/ksu_tuner/bin/tuner.sh apply gaming
sh /data/adb/modules/ksu_tuner/bin/tuner.sh fast gaming  # 只切 CPU/GPU/VM，快一些
sh /data/adb/modules/ksu_tuner/bin/tuner.sh monitor      # 连采 3 次实时数据
sh /data/adb/modules/ksu_tuner/bin/tuner.sh revert       # 回滚所有内核参数
sh /data/adb/modules/ksu_tuner/bin/tuner.sh set CPU_GOV 0
sh /data/adb/modules/ksu_tuner/bin/tuner.sh trim

# 智能驾驶
sh .../bin/autopilot.sh start | stop | status
sh .../bin/autopilot.sh once     # 只跑一次决策，看看现在会选哪档

# 电池守护
sh .../bin/guard.sh start | stop | status
sh .../bin/guard.sh node         # 看识别到了哪个控制节点

# 应用待机
sh .../bin/appctl.sh list
sh .../bin/appctl.sh set com.xxx.yyy rare
sh .../bin/appctl.sh optimize    # 全部设成 rare
sh .../bin/appctl.sh hibernate   # 杀掉后台（跳过前台应用）

# 应用策略
sh .../bin/appwatch.sh set com.xxx.yyy gaming
sh .../bin/appwatch.sh fg        # 看当前识别到的前台包名

# 自定义参数
sh .../bin/custom.sh add /proc/sys/vm/swappiness 100
sh .../bin/custom.sh apply
sh .../bin/custom.sh revert

# 显示
sh .../bin/display.sh status
sh .../bin/display.sh apply gaming
```

`status` 的输出是 `KEY=VALUE` 格式，好解析：

```
CFG_PROFILE=balanced
LIVE_GOVERNOR=walt
LIVE_CUR_FREQ=1286400
LIVE_GPUFREQ=490
...
```

---

## 配置文件

`/data/adb/ksu_tuner/config.conf`，`KEY=VALUE` 一行一条。重复的键以**最后一条**为准。

主要几个：

| 键 | 说明 |
|---|---|
| `PROFILE` | 当前预设 |
| `CPU_GOV` `GPU_TUNE` `IO_SCHED` `READ_AHEAD` `VM_TUNE` `NET_TUNE` `DNS_TUNE` `ZRAM_TUNE` | 各子系统开关，1 开 0 关 |
| `THERMAL_OPEN` | 温控解锁，默认关 |
| `SELINUX_PERM` | SELinux 宽容，默认关 |
| `AUTOPILOT` `AUTO_BASE` `AUTO_COOL` `AUTO_TEMP_HIGH` `AUTO_TEMP_LOW` `AUTO_SCREEN` `AUTO_CHARGE` | 智能驾驶 |
| `BATT_GUARD` `CHARGE_LIMIT` | 电池守护 |
| `APPWATCH` `WATCH_BASE` | 应用策略 |
| `DISP_TUNE` | 显示调优 |

温度阈值单位是毫摄氏度，`45000` = 45°C。

改完不用重启，跑一次 `tuner.sh apply` 就生效。

---

## 目录结构

```
/data/adb/modules/ksu_tuner/
├── module.prop
├── customize.sh           安装时初始化配置、设权限
├── post-fs-data.sh        建目录、校验配置、识别 late-load
├── service.sh             开机应用预设、拉起守护进程
├── boot-completed.sh      动画缩放、自动 fstrim、刷新模块描述
├── action.sh              动作按钮
├── uninstall.sh           卸载时完整还原
├── initrc/
│   └── ksu_tuner.rc       init 常驻服务
├── bin/
│   ├── tuner.sh           主控，预设应用与状态查询
│   ├── autopilot.sh       温度/息屏/充电自适应
│   ├── guard.sh           充电上限
│   ├── appctl.sh          Standby Bucket 管理
│   ├── appwatch.sh        前台应用追踪
│   ├── custom.sh          自定义参数
│   ├── display.sh         刷新率与触控
│   └── init-apply.sh      initrc 调用的入口
└── webroot/
    └── index.html         WebUI（单文件，无外部依赖）
```

运行时数据在 `/data/adb/ksu_tuner/`：`config.conf` 配置、`backup.conf` 原始值备份、`tuner.log` 日志、各守护进程的 `.pid` 和 `.log`。

---

## 几个坑

**温度阈值别设太低。** 设 40°C 的话日常刷个网页都会触发降温，得不偿失。45~50 比较合理。

**温控解锁和 SELinux 宽容默认关着是有原因的。** 前者会让机身明显更热，长期高温反而伤电池；后者降低安全强度，调试完就该关掉。这俩我不建议长期开着。

**自定义参数改之前先确认节点含义。** 虽然能还原，但写错值可能当场就卡住，得进 recovery 删文件。不确定的先 `cat` 一下看看当前值和取值范围。

**AppWatch 和 AutoPilot 别同时开。** 两个都在抢着切预设，会打架。动作按钮的循环顺序已经考虑到了这点，但手动配置时容易踩。

**`revert` 之后记得重新 `apply`。** 回滚是把值恢复成模块第一次写入前的样子，此时配置里的开关还是开的，不重新应用的话状态和配置就对不上了。

**WebUI 首次打开会读一圈状态，大概 1~2 秒。** 标签页是懒加载的，切到「应用管理」才开始拉应用列表，应用多的话会再等一会儿。

---

## 卸载

直接在管理器里删就行，`uninstall.sh` 会：

1. 杀掉所有守护进程
2. 还原自定义参数和内核参数
3. 恢复应用待机档位到 `frequent`
4. 恢复刷新率和触控设置
5. 清掉 `/data/adb/ksu_tuner/`

如果哪个环节没跑成功，`backup.conf` 里还有原始值，手动写回去就行。

---

## 测试情况

主控和守护进程都留了注入点，方便不刷机验证逻辑：

- `KSU_SYS=<路径>` 把 `/sys`、`/proc` 的读取重定向到别处
- `autopilot.sh once` 只跑一次决策
- `appwatch.sh fg` / `once` 单独看前台识别结果

我用这套跑了这些场景：

- AutoPilot 决策矩阵 12 组（常规 / 息屏 / 过热 / 临界 45°C / 充电提速 / 改基准档 / 关息屏省电 / 动态改阈值）
- 冷却滞回时序（46°C 触发 → 43°C 保持 → 39°C 解除）
- BatteryGuard 充放电循环 5 组（85% 断电 / 79% 保持 / 76% 恢复 / 再次断电 / 停止时恢复充电）
- 前台识别 7 组（含 3 级回退链、多用户、特殊包名）
- 自定义参数增删改查、非法路径拦截、节点缺失降级

在骁龙 8 Gen 2 / 内核 5.10.236 的机器上实机验证通过。

---

## 许可

GPL-3.0
