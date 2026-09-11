# 记账本（accounts_keep_test）

本地优先的个人记账 App。Android 优先交付，界面简体中文，货币人民币。
**全部数据保存在本机，App 不申请网络权限，完全离线可用。**

## 功能

| 模块 | 说明 |
|---|---|
| 记一笔 | 收入 / 支出 / 转账；金额、分类、账户、日期时间、交易对象、备注；转账支持手续费 |
| 账户与余额 | 现金、储蓄卡、支付宝、微信、信用卡；自动余额、净资产、总资产/总负债；信用卡以「待还款」呈现 |
| 账单 | 按日分组、每日小计；按时间范围/类型/账户/分类/关键词筛选；软删除记录可一键撤销 |
| 统计 | 分类占比饼图、近 12 个月收支柱状趋势、收支对比（日均支出、笔数、单笔最高）、结余 |
| 分类管理 | 内置 16 个常用中文分类，可增删改；被引用的分类只能归档（历史数据不受影响） |
| 数据 | 导出 JSON 完整备份与 CSV 流水表；导入支持「合并 / 覆盖」并给出差异预览 |

## 快速开始

本机环境已验证：Flutter 3.41.6 / Dart 3.11.4、JDK 21、Android SDK（platform 36）、
Gradle 8.14。

```bash
flutter pub get
flutter analyze          # 期望：No issues found!
flutter test             # 期望：全部通过（当前 191 个用例）
flutter run              # 需要已连接的 Android 设备或模拟器
flutter build apk --debug
```

### 本机构建环境的三个已知坑

1. **Windows 需开启「开发者模式」**（设置 → 系统 → 开发者选项 → 开发人员模式）。
   否则 Flutter 无法为含插件的工程创建符号链接，`flutter pub get` 会以
   `ERROR_PRIVILEGE_NOT_HELD` 收尾。
2. **Android SDK 路径**必须让 Gradle 能找到。若 `android/local.properties` 里的
   `sdk.dir` 不正确（本机首次生成时被写成了 `E:\Program Files`），构建会以
   `LicenceNotAcceptedException` 之类的错误失败。两种修法：
   在环境变量里设置 `ANDROID_HOME=<SDK 路径>`，或直接修正
   `android/local.properties` 的 `sdk.dir`。本机可用：
   `E:\SDK\Android`。
3. **Gradle 发行包**由 `android/gradle/wrapper/gradle-wrapper.properties` 指定。
   默认的 `-all` 包约 200 MB，首次下载容易长时间无输出甚至卡住；改用
   `gradle-8.14-bin.zip`（约 131 MB）即可。若网络不稳，可先手动下载到
   `~/.gradle/wrapper/dists/gradle-8.14-bin/<hash>/gradle-8.14-bin.zip.part`
   再让 Gradle 自己完成校验与解压。

另外，本工程刻意不声明 `ndkVersion`：项目不含任何原生代码，声明它只会迫使本机
下载数百 MB 的 NDK 并要求接受其许可证（详见 `android/app/build.gradle.kts` 注释）。

## 用 Android Studio 打开

1. **File → Open**，选择工程**根目录**（`E:\code\accounts_keep_test`）。
   ⚠️ 不要选 `android` 子目录，否则会被当成纯 Gradle 工程，Dart/Flutter 支持失效。
2. 等自动 `pub get` 与索引结束；运行配置会自动出现 **main.dart**，点 ▶ 即可。
3. 本机 Android Studio 2025.1.3 已装好 Dart 与 Flutter 插件，Flutter SDK 路径
   （`E:/SDK/flutter_windows_3.41.6-stable/flutter`）与 Android SDK
   （`E:/SDK/Android`）均已登记，无需再配置。

### 模拟器

本机已创建并可直接使用的 AVD：

| 项 | 值 |
|---|---|
| 名称 | `accounts_keep_api36` |
| 系统镜像 | `system-images;android-36;google_apis;x86_64` |
| 设备档 | Pixel 6（1080×2400 @420dpi） |
| 内存 / 堆 | 4 GB / 512 MB（已从默认 2 GB / 228 MB 调高，避免 Flutter 渲染异常） |
| 硬件加速 | WHPX（Windows Hypervisor Platform），已确认可用 |

命令行启动：

```bash
flutter emulators --launch accounts_keep_api36
# 或（推荐，见下）
powershell -ExecutionPolicy Bypass -File .\tools\start-emulator.ps1
# 或（不会摆正窗口）
E:\SDK\Android\emulator\emulator.exe -avd accounts_keep_api36 -gpu auto
```

Android Studio 里则通过 **Device Manager → accounts_keep_api36 → ▶** 启动。

### 模拟器窗口会跑到屏幕外（已提供启动器）

本机主屏工作区只有 **2293×912**，而模拟器按「Pixel 6 + 420dpi」推算出的窗口高约
**951px**，比屏幕还高，于是它把窗口顶部顶到屏幕外（实测 `y = -480`），标题栏与上半屏
都看不见。

模拟器**每次启动都会自己重算位置**：它既不读 Qt 保存在
`HKCU\Software\Google\AndroidEmulator` 的 `geometry`，也不受 `-scale`（2.0 起已忽略）
与 `-fixed_scale` 影响。所以唯一可靠的办法是启动后再把窗口摆正一次 —— 即
`tools/start-emulator.ps1` 做的事：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\start-emulator.ps1
```

它会启动 AVD、等到窗口出现后调用 Win32 `MoveWindow` 把窗口移到 `(60,20)`、尺寸
约 394×881（完整落在工作区内），然后等 Android 启动完成。可传参调整：

```powershell
# 换位置/大小，或换 AVD
powershell -ExecutionPolicy Bypass -File .\tools\start-emulator.ps1 -X 100 -Y 10 -Width 420 -Height 860
powershell -ExecutionPolicy Bypass -File .\tools\start-emulator.ps1 -Avd 其它名称 -NoFix
```

> `tools/start-emulator.ps1` 刻意保持**纯 ASCII**：Windows PowerShell 5.1 在没有 BOM 时
> 按 ANSI 代码页读取 `.ps1`，非 ASCII 注释会被解码坏并破坏脚本解析。

在 Android Studio 里启动的模拟器窗口若同样偏高，直接拖动标题栏即可；如果标题栏已经
在屏幕外，用 `Win + ↑`（最大化）或 `Alt + 空格 → 移动` 把它拉回来。

## 真机/模拟器验收记录

已在 API 36 模拟器上完成一次端到端人工走查（非测试框架、真实安装包）：

| 验证项 | 结果 |
|---|---|
| APK 安装 | `adb install` 成功（1 秒） |
| 冷启动 | 首页正常渲染，无崩溃（`logcat -b crash` 为空） |
| 中文与主题 | 中文文案、Material 3 配色、底部四项导航均正确 |
| 首次启动 | 自动写入账本，落在 `/data/data/<包名>/app_flutter/accounts_keep/ledger.json` |
| 落盘内容 | `schemaVersion: 1` 信封结构正确，5 个默认账户 + 16 个分类，0 条流水 |
| 记一笔 | 输入 `12.34` → 选「餐饮」→ 保存成功 |
| 落盘校验 | `amountCents: 1234`、`accountId: acc_cash`、`categoryId: cat_food`、`occurredAtUtc` 带 `Z`、`utcOffsetMinutes` 一并写入 |
| 界面刷新 | 净资产 `-¥12.34`、本月支出 `¥12.34`、结余 `-¥12.34`、最近流水一条（餐饮 · 今天 · 现金） |
| **杀进程重启** | `am force-stop` 后重新启动，数据完整保留 ✅ |

> 应用数据目录注意：`path_provider` 的 `getApplicationDocumentsDirectory()` 在 Android 上
> 返回的是 `<应用数据目录>/app_flutter`，**不是** `files/`，排查数据文件时别找错地方。

## 架构

```
lib/
  core/        纯工具：金额（分为单位）、日期/月键、Result、JSON 解析、平台能力出口
  domain/      纯 Dart 领域层：模型 + 不变量 + 选择器（统计）+ 筛选条件；零 Flutter 依赖
  data/        存储与仓库：单文件 JSON 原子写入、仓库、导入导出、CSV、种子数据
  state/       界面偏好（主题、货币符号），随账本持久化
  ui/          Material 3 界面：首页 / 记账 / 账单 / 统计 / 账户 / 分类 / 设置
test/          单元测试 + Widget 测试（191 例）
docs/          api_reference / data_format / testing / harmony_migration
tools/         start-emulator.ps1（启动模拟器并摆正窗口）
screenshots/   人工验收截图（已 gitignore）
android/       Android 工程；windows/ 为 flutter create 附带脚手架，当前非交付目标
```

各层类型与 API 速查见 [`docs/api_reference.md`](docs/api_reference.md)。

关键设计决策：

1. **金额一律用整数「分」**，只在输入与展示边界转换，杜绝浮点误差。
2. **单文件 JSON + 原子写入（临时文件 → rename）+ `.bak` 回退**，不引入原生 ORM，
   既简化备份/迁移，也为鸿蒙适配留路（见 `docs/harmony_migration.md`）。
3. **同时保存 UTC 瞬时与记账时的时区偏移**，保证设备时区变化后历史账目的
   日期与月份归属不漂移。
4. **平台能力只允许出现在 `lib/core/platform_bridge.dart`**，全工程唯一原生插件
   是 `path_provider`。
5. **软删除 + 撤销**，避免误删；有流水的账户删除时必须选择「归档」或「迁移流水」。
6. 任何破坏兼容的结构变更都要递增 `schemaVersion` 并在 `LedgerData.fromJson` 补迁移。

详细数据格式见 [`docs/data_format.md`](docs/data_format.md)。

## 测试

```bash
flutter test                                   # 全部用例
flutter test test/selectors_test.dart          # 统计与余额计算
flutter test test/persistence_test.dart        # 落盘、损坏回退、版本校验
flutter test test/repository_errors_test.dart  # 落盘失败回滚（模拟磁盘故障）
flutter test test/entry_flow_test.dart         # 记一笔闭环（Widget）
flutter test --coverage                        # 生成 coverage/lcov.info
```

当前状态（本机实测）：

| 指标 | 结果 |
|---|---|
| `flutter analyze` | No issues found! |
| `flutter test` | **191 个用例全部通过** |
| 行覆盖率（全工程） | 85.3% |
| 行覆盖率 core / domain / data / state | 97.5% / **94.2%** / 88.8% / 100% |
| `flutter build apk --debug` | 成功，产物 `build/app/outputs/flutter-apk/app-debug.apk` |

覆盖重点：金额解析与格式化边界、交易不变量（含转账与手续费）、
**转账不改变净资产**、信用卡符号语义、跨月/跨年/闰月边界、筛选组合、
JSON 往返一致、损坏文件回退到备份、未来版本数据拒绝加载、导入合并统计、
**落盘失败时内存态回滚且不丢数据**。
UI 层覆盖率（约 58%）只反映 Widget 测试覆盖面，并非质量指标。

测试怎么写、工具类怎么用、有哪些已知缺口，见 [`docs/testing.md`](docs/testing.md)。

## 文档索引

| 文档 | 内容 |
|---|---|
| [`docs/api_reference.md`](docs/api_reference.md) | 分层依赖方向、各层核心类型与 API 速查、`wallClock` 三个时间访问器的语义差异 |
| [`docs/data_format.md`](docs/data_format.md) | JSON 信封与字段定义、为什么用「分」、为什么同时存 UTC 与偏移、自愈规则、CSV 列定义、导入策略 |
| [`docs/testing.md`](docs/testing.md) | 怎么跑、当前基线、各测试文件分工、测试工具、约定与已知缺口 |
| [`docs/harmony_migration.md`](docs/harmony_migration.md) | 已落地的可迁移性决策、迁移步骤、风险与应对 |

## 已知限制（MVP 范围外）

云端同步与多设备、预算与超支提醒、周期性账单、多账本、多币种、
支付宝/微信对账单导入、二级分类的界面（数据结构已预留）、分享到系统（导出文件写在
应用文档目录并在界面展示路径）。
