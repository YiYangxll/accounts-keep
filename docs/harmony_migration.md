# 鸿蒙（OpenHarmony）迁移清单

本工程当前交付目标为 **Android 优先**，同时刻意把架构整理成「迁移时只改一层」。
本文记录已经做过的可迁移性决策、迁移时的具体步骤，以及已知风险。

> 结论先说：**domain / data / ui 三层不需要为鸿蒙改动**，需要动的只有
> `lib/core/platform_bridge.dart` 一个文件，加上工程脚手架与依赖来源。

---

## 1. 已经做好的可迁移性决策

这些不是「以后再说」，而是当前代码里已经落地的约束：

| 决策 | 落地位置 | 迁移收益 |
|---|---|---|
| 领域层零 Flutter 依赖（纯 Dart） | `lib/domain/**` 只 import `dart:*` 与其它 domain 文件 | 可直接复用到任何 Dart 运行环境 |
| 平台能力收敛到唯一出口 | `lib/core/platform_bridge.dart` 是全工程唯一 import `path_provider` 的地方 | 迁移时只替换这一个文件 |
| 不引入原生 ORM | 用单文件 JSON + 原子写入（`lib/data/storage/ledger_storage.dart`） | 避开 sqflite / drift / isar 的原生绑定，这是鸿蒙适配中最大的坑 |
| 不引入 `shared_preferences` | 偏好随账本存进同一个 JSON（`LedgerData.preferences`） | 少一个原生插件 |
| 不引入 `share_plus` 等系统交互插件 | 导出写到应用文档目录下的 `exports/`，界面展示路径 | 少两个原生插件 |
| 图表用纯 Dart | `fl_chart` | 无原生代码 |
| 其余依赖均为纯 Dart | `uuid` / `collection` / `intl` | 无原生代码 |
| 语言基线保守 | `pubspec.yaml` 声明 `sdk: '>=3.4.0 <4.0.0'`，不使用仅新 SDK 提供的语法（例如 Dart 3.9 的 dot-shorthands） | 能直接切到鸿蒙的 Flutter 分支，无需改语法 |
| 渲染层只用 Material 组件 | 无自定义 PlatformView、无 `dart:ffi` | 无引擎层适配工作量 |

**最终原生插件清单：只有 `path_provider` 一个。**

---

## 2. 迁移步骤

### 步骤 0：先做工具链可行性验证（不要跳过）

鸿蒙的 Flutter 支持由 OpenHarmony 社区分支提供，**对 Flutter 版本有强约束**，
且需要 DevEco Studio / OpenHarmony SDK / hvigor 等额外工具链。已知社区维护的分支
集中在 3.7 / 3.22 / 3.27 等版本线上（参见
[Flutter-OH 版本演进规划和分支策略](https://cloud.tencent.com.cn/developer/article/2530843#1)、
[鸿蒙版 Flutter 各版本获取指南](https://cloud.tencent.cn/developer/article/2536940#1)）。

**第一步应当是**：选定鸿蒙 Flutter 分支 → 用它跑通官方 hello world →
确认 `flutter doctor` 无阻塞，再动本工程。若选到的分支低于 3.22，
需要重新核对 `pubspec.yaml` 的 SDK 下限与各依赖的版本区间。

### 步骤 1：替换平台能力实现

`PlatformBridge` 目前只有一个能力：

```dart
Future<Directory> documentsDirectory() async {
  final Directory dir = await getApplicationDocumentsDirectory();
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}
```

迁移时改成鸿蒙的实现（或在该文件内按平台分支），其余代码一行不改。
需确认的目标语义：返回应用私有、**不会被系统自动清理**、无需额外权限的目录。
若鸿蒙侧的可用目录语义不同（例如只能拿到沙箱内的 files/cache 子目录），
务必选**非 cache** 的那个，否则账本可能被系统回收。

### 步骤 2：生成鸿蒙工程脚手架

在工程内生成 `ohos/`（由鸿蒙 Flutter 分支的 `flutter create --platforms=ohos .` 提供），
并核对：

* `ohos/` 内的应用包名与 Android 侧一致（当前 `com.example.accounts_keep_test`）。
* 应用名与图标。
* **不申请网络权限**（与 Android 侧一致，本应用完全离线）。

### 步骤 3：替换插件的鸿蒙实现

`path_provider` 需替换为 OpenHarmony 兼容实现。社区维护有
[flutter_packages（OpenHarmony 兼容适配项目）](https://atomgit.com/CPF-Flutter/flutter_packages/tree/e475b5e137a33b73a3a6bb00d05d41bbdd49f939#1)，
其中包含一批社区插件的鸿蒙适配版本。若 `path_provider` 有对应实现，改为
`dependency_overrides` 指向该仓库即可；若没有，就在步骤 1 里自行实现
（走 MethodChannel 拿沙箱目录）。

### 步骤 4：验证清单

| 项目 | 验证方式 |
|---|---|
| 编译 | 鸿蒙目标 `flutter build` 成功 |
| 四项核心功能 | 真机走查：记一笔 → 账单筛选 → 统计报表 → 账户余额 |
| 持久化 | 杀进程重启后数据仍在 |
| 导入导出 | 导出 JSON/CSV → 文件存在 → 重新导入数据一致 |
| 金额精度 | 回归 `test/money_test.dart`（与平台无关，`flutter test` 即可） |
| 领域逻辑 | 回归 `test/selectors_test.dart` 等纯 Dart 测试 |

---

## 3. 已知风险与应对

| 风险 | 影响 | 应对 |
|---|---|---|
| 鸿蒙 Flutter 分支版本低于当前开发版本 | 语言特性与 API 可能不可用 | 已把基线压到 3.22/Dart 3.4；迁移前先确认分支版本 |
| `path_provider` 无鸿蒙适配 | 无法取得数据目录，App 不可用 | 唯一强依赖，已收敛到 `PlatformBridge`；最坏情况自行用 MethodChannel 实现，工作量约 1 个文件 |
| 文档目录语义差异（可能落到 cache） | 数据被系统清理 | 步骤 1 中显式校验目录语义，并用「杀进程 + 系统清理后重启」验证 |
| 中文文本渲染差异 | 极端字符缺字形 | 已使用系统字体回退；如出现缺字需在 `AppTheme` 中指定鸿蒙可用中文字体 |
| `fl_chart` 渲染差异 | 图表显示异常 | 纯 Dart 绘制，风险低；异常时降级为自绘 `CustomPaint` 柱状/饼图 |
| 打包与签名流程不同 | 无法产出安装包 | 属工具链问题，随步骤 0 一并验证 |

---

## 4. 明确不做的事

* 不生成 `ohos/` 脚手架，不引入任何鸿蒙专有插件（当前交付目标是 Android）。
* 不为了「可能将来要迁移」而在代码里到处写平台判断分支——平台差异只允许出现在
  `lib/core/platform_bridge.dart`。这条约束请在后续开发中保持。
