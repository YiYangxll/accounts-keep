# 代码导读与核心 API

给后续维护者（以及几个月后的自己）的一页速查表。设计取舍与数据格式分别见
[`data_format.md`](data_format.md) 与 [`harmony_migration.md`](harmony_migration.md)。

---

## 1. 分层与依赖方向

```
ui/ ──▶ state/ ──▶ data/ ──▶ domain/ ──▶ core/
                                    └──▶ (dart:* 与纯 Dart 包)
```

* `domain/` **零 Flutter 依赖**（只 import `dart:*`、其它 domain 文件与 `core/`），
  因此可以被纯 Dart 测试直接覆盖，也是鸿蒙迁移时唯一不需要改的一层。
* `core/platform_bridge.dart` 是全工程**唯一** import `path_provider` 的文件。
* 依赖方向不可逆：`domain` 不允许 import `data`/`ui`。

---

## 2. core —— 与业务无关的工具

### `core/money.dart` · `Money`

金额统一以**整数分**表示。`Money` 是不可实例化的静态工具类。

| 成员 | 说明 |
|---|---|
| `centsPerUnit` / `unitsPerCent` | 100 / 0.01 |
| `maxCents` | 单笔上限 1 亿元（防误输与溢出） |
| `toUnits(cents)` | 分 → 元（double，仅用于图表） |
| `fromUnits(units)` | 元 → 分，四舍五入 |
| `tryParseUnitsToCents(raw)` | 解析用户输入，失败返回 `null` |
| `toPlainString(cents)` | `1234` → `"12.34"`（无符号、无千分位，负号保留） |
| `format(cents, {symbol})` | `123456` → `"¥1,234.56"` |
| `isValidAmount(cents)` | 是否为正且不超上限 |

输入解析容忍：首尾空白、`￥`/`¥`/`$`、千分位逗号、`+` 号、`12.`、`.5`；
超过两位小数按分四舍五入；拒绝负数、`1.2.3`、`1e3`、字母。

### `core/date_x.dart` · `MonthKey` 与 `DateTimeX`

`MonthKey` 是 `yyyy-MM` 的值对象：`of` / `tryParse` / `firstDay` / `lastDay` /
`nextMonthFirstDay` / `shift(n)` / `ordinal` / `label`（`2026年3月`）。

`DateTimeX` 扩展：`startOfDay`、`nextWeekStart`、`monthKey`、`isSameDay`、
`isSameMonth`、`dateText`（`yyyy-MM-dd`）、`dateTimeText`、`offsetMinutes`。

### `core/result.dart` · `Result<T>` 与 `Unit`

领域与数据层不抛裸异常，统一返回 `Result`：`isOk` / `isErr` / `value` / `error` /
`getOrElse` / `map` / `flatMap`。无返回值的成功用 `Result<Unit>.ok(Unit())`
（`void` 不能作为类型参数，故引入 `Unit` 作为占位）。

### `core/json_x.dart` · `JsonX` 与 `parseObjectList`

对持久化数据做**防御式解析**，字段缺失或类型不符一律抛 `CorruptDataError`，
绝不静默降级成默认值：

`requireString` / `optionalString` / `requireInt` / `optionalInt` / `requireBool` /
`requireMap` / `optionalMap` / `requireList` / `optionalList` /
`optionalDateTime` / `requireDateTime`。

> `optionalInt` 会把 `3.0` 归一化为 `3`；`optionalDateTime` 把空字符串当缺失，
> 但**非法时间会报错**——日历字段静默变 null 会污染月份归属与账期统计。

### `core/platform_bridge.dart` · `PlatformBridge`

```dart
Future<Directory> documentsDirectory()
```

全工程唯一平台能力出口。迁鸿蒙时只替换本文件（见 `harmony_migration.md`）。

---

## 3. domain —— 业务规则（纯 Dart）

### 枚举 `domain/enums.dart`

* `TxKind` — `expense` / `income` / `transfer`，附 `label`、`sign`
* `AccountKind` — `cash` / `debitCard` / `alipay` / `wechat` / `creditCard` / `other`，
  附 `label`、`isLiability`
* `CategoryKind` — `expense` / `income`，附 `label`、`asTxKind`

各枚举均提供 `tryParse`（未知值返回 `null`，由调用方决定抛错）。

### `domain/transaction.dart` · `Transaction`、`TxSplit`

一笔流水同时保存 **UTC 瞬时** 与 **记账时的时区偏移**，三个时间访问器语义不同，
这是本工程最容易踩的点：

| 访问器 | 语义 | 用途 |
|---|---|---|
| `occurredAtUtc` | 真实瞬时（UTC） | 持久化、跨设备比较 |
| `wallClock` | **墙上时间**，用 UTC 标记承载 | 月份归属、账单筛选（`monthKey` 基于它） |
| `wallClockLocal` | 同上但映射到设备本地时区 | 仅展示 |

⚠️ `wallClock` 是**组件语义**，不要对它与 `DateTime(...)` 做相等比较或用
`millisecondsSinceEpoch`（会随设备时区变化）。要比较就比
`year/month/day/hour/minute` 组件。

`validate()` 返回 `LedgerError?`（null 表示合法），检查：金额为正、手续费非负、
转账必须有且仅有不同的转入账户、收支必须有分类、分项之和等于总额且每项为正。

### `domain/account.dart` / `category.dart`

不可变模型 + `copyWith`（可空字段用 `clearXxx: true` 显式清空）+
`toJson`/`fromJson`（时间统一以 UTC 带 `Z` 落盘）。

### `domain/selectors.dart` · `Selectors`

**所有统计都在这里**，是纯函数、无副作用、易测：

| 方法 | 说明 |
|---|---|
| `active(txs)` | 去掉软删除记录 |
| `inMonth(txs, month)` / `inRange(txs, start, end)` | 按墙上时间过滤 |
| `summarize(txs)` | → `PeriodSummary`（收入/支出/转账/笔数/结余） |
| `accountBalance(account, txs)` | 单账户余额（含转账与手续费） |
| `balances(accounts, txs, {includeArchived})` | → `List<AccountBalance>` |
| `netWorth` / `totalAssets` / `totalLiabilities` | 净资产与资产/负债汇总 |
| `sortedByTimeDesc(txs)` | 时间倒序（同刻按 id 稳定） |
| `totalsByCategory(txs, {kind, categories})` | → `List<CategoryTotal>` |
| `withShares(totals)` | 补占比 → `List<CategoryShare>` |
| `monthlyTrend(txs, endMonth, monthCount)` | 近 N 月趋势 |
| `expenseByAccount(txs)` | 按账户汇总支出 |
| `changeRate(current, previous)` | 环比，基期为 0 返回 null |

**余额语义**：资产账户 = 期初 + 收入 − 支出 + 转入 − 转出 − 手续费；
信用卡余额**带符号**（负=欠款），因此净资产 = Σ 余额**无需特例**，
转账在两账户间一增一减、不影响净资产（仅手续费是真实支出）。

### `domain/transaction_filter.dart` · `TransactionFilter`

不可变筛选条件值对象：`preset`（`DateRangePreset`）、`customStart` /
`customEndExclusive`、`kinds`、`accountIds`、`categoryIds`、`keyword`、
`includeDeleted`。核心方法：

* `resolveRange({now})` → `LocalDateRange?`（左闭右开，`all` 返回 null）
* `matches(tx, {now})` / `apply(txs, {now})`
* `rangeLabel`、`activeFilterCount`、`isUnfiltered`、`copyWith`、`cleared()`

转账按**转出或转入账户**任一匹配即命中；关键词同时匹配备注、交易对象、标签，
以及金额的两种写法（`123.45` 与 `12345`）。

### `domain/ledger_error.dart`

密封类 `LedgerError`，每个子类自带可直接展示的中文 `message`：
`InvalidAmountError`、`InvalidTransferError`、`SameAccountTransferError`、
`AccountNotFoundError`、`CategoryNotFoundError`、`CategoryKindMismatchError`、
`MissingCategoryError`、`DuplicateNameError`、`EmptyNameError`、`AccountInUseError`、
`CategoryInUseError`、`StorageError`、`CorruptDataError`、`UnsupportedSchemaError`、
`MalformedImportError`、`UnknownEnumValueError`、`NotFoundError`。

---

## 4. data —— 持久化与仓库

### `data/ledger_data.dart` · `LedgerData`

内存中的完整账本快照（accounts / categories / transactions / preferences），
以及 `accountById`、`categoryById`、`transactionById`、`activeAccounts`、
`transactionCountForAccount/Category`、`hasAccountNamed`、`hasCategoryNamed`。

序列化有两个层次：

* `toJson()` — 只含账本内容
* `toEnvelopeJson({exportedAtUtc})` — 带 `schemaVersion` 的完整信封
* `encode()` — 落盘文本（= 信封 + 缩进）

**落盘与导出共用同一个信封格式**，因此备份文件可以直接当账本文件用。

`sanitize()` 是数据自愈入口：剔除重复 id、非法流水、悬空引用、类型不匹配的
分类引用，返回清洗后的数据与中文告警列表。

### `data/storage/ledger_storage.dart` · `LedgerStorage`

单文件 JSON + **原子写入**（写 `.tmp` → 旧文件转 `.bak` → rename）+ 损坏回退。

* `read()` → `Result<StorageReadResult>`（含 `warnings` 与 `recoveredFromBackup`）
* `write(data)` / `deleteAll()` / `exportDirectory()` / `writeExport(name, content)`
* `decodeForTest(raw)` — 仅供测试

读取失败的处理顺序：主文件 → `.bak` → 把损坏文件改名留档为 `.corrupt-<时间戳>`
→ 空账本并告警。**`schemaVersion` 高于当前支持版本时直接报错**，不做任何自动处理，
避免误读覆盖用户数据。

> 类未声明为 `final`，这是刻意的：测试用子类覆写 `write`/`read` 模拟磁盘故障，
> 以验证仓库的回滚行为（见 `test/repository_errors_test.dart`）。

### `data/ledger_repository.dart` · `LedgerRepository extends ChangeNotifier`

写操作统一遵循 **校验 → 改内存 → 落盘 → 通知**，落盘失败**回滚内存**，
保证界面看到的状态与磁盘一致。

* 生命周期：`load()`、`isReady`、`lastRead`、`acknowledgeWarnings()`
* 流水：`addTransaction` / `updateTransaction` / `deleteTransaction`（软删）/
  `restoreTransaction`
* 账户：`addAccount` / `updateAccount` / `removeAccount`（仅无流水时物理删除）/
  `deleteAccount(id, {strategy, migrateToAccountId})` / `restoreAccount`
* 分类：`addCategory` / `updateCategory` / `deleteCategory`（返回 `true`=已删除、
  `false`=已归档）/ `restoreCategory`
* 导入：`replaceAll(data)` / `mergeIn(data)`
* 偏好：`preference(key)` / `setPreference(key, value)`
* 工具：`newId(prefix)`、`storage`、`data`

`AccountDeletionStrategy.archive` 保留历史流水（推荐）；`.migrate` 把流水迁到
另一账户后删除本账户。

### `data/import_export.dart` · `LedgerTransfer`

纯函数，不碰文件系统：`exportJson` / `exportCsv` / `decodeJson` / `preview`
与 `outcomeFromPreview(preview, strategy)`。

### `data/ledger_importer.dart` · `LedgerImporter`

导入编排：`prepare(raw)` 解析并生成差异预览 → `apply(data, strategy, preview: ...)`
落库并返回 `ImportOutcome` 统计。UI 层必须在 `apply` 前把预览展示给用户确认。

### `data/csv_codec.dart` / `data/seed_data.dart`

`encodeCsv` / `decodeCsv`（RFC 4180，默认写 UTF-8 BOM）；`seedAccounts()` /
`seedCategories()` 提供 5 个默认账户与 16 个中文分类，**不注入任何假流水**。

---

## 5. state / ui

* `state/settings_controller.dart` — 主题模式与货币符号，随账本 JSON 持久化
  （因此不需要 `shared_preferences`）。
* `ui/shell/home_shell.dart` — 底部四项导航 + 「记一笔」FAB。
* `ui/` 其余页面：首页、记账、账单与筛选、统计、账户、分类管理、设置。
* `ui/common/` — 金额/日期格式化、图标名映射、流水列表项、空状态与对话框。

**图标与颜色以「名字」持久化**（`iconName`、`colorHex`），由
`ui/common/icon_map.dart` 映射到具体 `IconData` 与 `Color`，
从而让 `domain` 保持零 Flutter 依赖。
