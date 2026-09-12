# 测试指南

## 1. 怎么跑

```bash
flutter analyze                                  # 期望：No issues found!
flutter test                                     # 全部用例
flutter test --coverage                          # 生成 coverage/lcov.info

# 只跑某一块
flutter test test/invariants_test.dart           # 不变量测试（最值得跑，改动账目逻辑必跑）
flutter test test/selectors_test.dart            # 余额与统计口径
flutter test test/persistence_test.dart          # 落盘、损坏回退、版本校验
flutter test test/repository_errors_test.dart    # 落盘失败回滚
flutter test test/entry_flow_test.dart           # 记一笔闭环（Widget）
flutter test test/entry_layout_test.dart         # 表单布局与浮动标签
flutter test test/home_refresh_test.dart         # 首页数字刷新（Widget）
flutter test test/bills_filter_test.dart         # 账单筛选交互（Widget）
flutter test --plain-name "转账"                  # 按用例名筛选
```

## 2. 当前基线

| 指标 | 值 |
|---|---|
| 用例总数 | **240**（另有 1 条标记 `skip`，原因见用例注释） |
| 行覆盖率（全工程，含 `.g.dart` 与 `test/`） | 79.1% |
| 仅 `lib/`：`core` / `domain` / `data` / `state` / **`ui`** | 97.5% / 95.2% / 88.5% / 100% / **68.8%** |

覆盖率查看（Windows 上不一定有 `lcov`，可用 PowerShell 直接汇总）：

```powershell
$rows=@(); $cur=$null
foreach($l in (Get-Content coverage/lcov.info)){
  if($l -like 'SF:*'){ $cur=[ordered]@{File=$l.Substring(3);LF=0;LH=0} }
  elseif($l -like 'LF:*'){ $cur.LF=[int]$l.Substring(3) }
  elseif($l -like 'LH:*'){ $cur.LH=[int]$l.Substring(3) }
  elseif($l -eq 'end_of_record' -and $cur){ $rows+=[pscustomobject]$cur; $cur=$null }
}
$th=($rows|Measure-Object LH -Sum).Sum; $tl=($rows|Measure-Object LF -Sum).Sum
"总: $th / $tl = {0:N1}%" -f (100.0*$th/$tl)
$rows | Sort-Object { $_.LH/$_.LF } | ForEach-Object { "{0,5:N0}%  {1}" -f (100.0*$_.LH/$_.LF), $_.File }
```

> ⚠️ 不要用 `$lines` / `$input` / `$matches` 之类的名字存中间结果：它们是
> PowerShell 的自动变量，赋值会被静默丢弃，于是统计出 0 条记录并除零。

## 3. 测试文件分工

| 文件 | 覆盖内容 |
|---|---|
| `money_test.dart` | 分/元转换与四舍五入、容错输入、拒绝非法输入、千分位格式化、上下限 |
| `domain_test.dart` | `Transaction` 全部不变量、序列化往返、未知枚举报错、月键边界（跨年/闰月）、时区归属 |
| `domain_models_test.dart` | 三个枚举的标签/解析、`copyWith` 全字段与 `clearXxx`、各错误的文案 |
| `selectors_test.dart` | 余额（含转账与手续费）、**转账不改变净资产**、信用卡符号、月度汇总、分类聚合占比、12 月趋势、按账户汇总 |
| `filter_test.dart` | 时间区间左闭右开边界、上月/近三月/近一年/自定义、类型与账户组合、转账双向匹配、关键词（含金额两种写法）、软删除可见性、**筛选条件计数与「自定义」chip 文案** |
| `core_utils_test.dart` | `Result` 三态、`JsonX` 正常读取与**防御式报错**、日期扩展、`SettingsController` 持久化 |
| `persistence_test.dart` | 原子写入、`.bak` 生成与回退、`.corrupt-*` 留档、JSON 数字解析（`schemaVersion`）、时间以 UTC 落盘、清洗悬空引用、清空与导出 |
| `repository_test.dart` | 首次加载种子数据、流水/账户/分类 CRUD、软删除与撤销、重名拒绝、账户归档与流水迁移、分类归档 vs 删除、偏好持久化 |
| `repository_errors_test.dart` | **模拟磁盘故障**：写失败回滚内存、已有数据不丢、迁移失败保持原样、合并/替换失败 |
| `import_export_test.dart` | CSV 转义与 BOM、导出内容、JSON 往返一致、缺 `schemaVersion`/版本过高/非法 JSON 的拒绝、导入差异统计 |
| `entry_flow_test.dart` | Widget：填金额选分类保存、空金额与未选分类的拦截、转账字段切换、分类随类型过滤 |
| `entry_layout_test.dart` | Widget 布局：标签必须落在自己框内且不越界到相邻控件、输入框互不重叠、字号放大到 1.5 倍无 overflow、窄屏可滚到保存按钮 |
| `category_customisation_test.dart` | 图标目录与配色板自检、分类新增/编辑可选图标与颜色、已归档分组与恢复按钮渲染、记一笔页的「管理」入口与用自定义分类记账、分类归档/恢复的仓库契约 |
| `home_refresh_test.dart` | Widget：仓库数据变化后首页四个数字（净资产 / 本月收入 / 本月支出 / 结余）与「最近流水」立刻刷新；转账不进收支；跨月流水只进列表不进本月合计；软删除与恢复；最近流水 20 条截断；下拉刷新；净资产卡片跳账户页 |
| `bills_filter_test.dart` | Widget：筛选面板的完整链路（默认视图 → 勾选 → 应用 → 重置 / 取消 / 清除 → 空状态）、分类/关键词/交易对象/类型/软删除/时间预设/自定义区间、筛选徽标与区间标签、底部导航切页后筛选不丢 |
| `invariants_test.dart` | **不变量测试（属性测试）**：随机操作序列下账本必须永远自洽，详见第 4 节 |

## 4. 不变量测试（`invariants_test.dart`）

这是本工程最有价值的一套测试。它不逐条枚举"应该怎样"，而是先定义
**一个健康账本必须永远满足的规则**，然后用随机操作序列反复冲击。

### 4.1 为什么需要它

手工枚举用例只能覆盖想得到的路径。记账应用真正的风险在于
「**任意操作序列之后账目是否还自洽**」——例如"先归档账户、再往该账户记一笔收入、
然后编辑一笔转账的手续费"这种组合。只有随机序列 + 不变量断言才能覆盖到。

### 4.2 不变量清单（`expectInvariants`，每一步之后都断言）

| # | 不变量 | 说明 |
|---|---|---|
| 1 | 引用完整性 | 每条流水都能解析到账户/转入账户/分类；转出与转入不同；分类类型与交易类型一致；流水自身 `validate()` 通过 |
| 2 | 金额合法 | 金额为正且不超上限；手续费非负 |
| 3 | 主键唯一 | 流水 id、账户 id、分类 id 均不重复；账户名与分类名非空 |
| 4 | **金额守恒** | `净资产 == (全部期初 + 全部收入 - 全部支出 - 全部手续费) - 归档账户余额合计` |
| 5 | 口径自洽 | 净资产 == 未归档账户余额之和；结余 == 收入 − 支出 |
| 6 | 聚合不丢钱 | 按分类聚合的支出合计 == 支出总额（分类归档也不能丢） |
| 7 | 月份归属可算 | 每笔流水的 `monthKey` 落在合理范围（1–12 月，2000–2100 年） |

> 第 4 条刻意写成「先算全量、再减去归档部分」。如果写成「只统计非归档账户」，
> 一旦归档账户的流水影响被错误计入或漏计，两边会同时错、把 bug 掩盖掉。
> 这个写法正是它在开发中抓出问题的地方（详见 4.4）。

### 4.3 覆盖面

* **5 组固定种子**（1 / 7 / 42 / 2026 / 999983），每组 **220 步**随机操作。
  种子固定，失败可复现：日志会打印完整操作序列，照着跑一遍就能重现。
* 操作种类与权重：收入 22%、支出 24%、转账 12%、编辑 8%、软删/撤销 8%、
  **故意非法输入 8%**、增改删分类 10%、增删账户 8%。
* 金额边界：1 分、1 亿元（上限）、小额、以及**超限/为负/为 0** 等非法值。
* 时间：2014–2027 年间随机日期，覆盖跨年与闰月。
* 另有 4 组定向测试：固定序列（含收入）、金额边界值、转账资产守恒、
  收入不影响账目一致性、随机收支后重载逐字段一致。

### 4.4 它抓到过的真实问题

* **归档账户的净资产的归口**：归档前净资产是 1000000，归档后是 0（符合「归档即
  不参与统计」的设计）；但如果守恒公式仍把该归档账户上的收入加回去，
  差额就会凭空出现。第 4 条的写法让这个差额暴露出来，而不是被掩盖。
* 因此 `Selectors.netWorth` 补了 `includeArchived` 参数（默认 `false`），
  并在文档注释里写明「归档账户整体不计入，连它流水的影响也一并排除」。

### 4.5 怎么扩充

1. 想加一类新操作？在 `Fuzzer._oneStep` 的分支里加，并给它一个权重。
2. 想加一条规则？在 `expectInvariants` 里加一个断言 —— 它会在**每一步之后**生效。
3. 失败时先读日志里的操作序列；把 `Fuzzer` 的种子换成失败那个，
   用 `run(repo, steps: N)` 逐步逼近，就能定位到具体是哪一步破坏了哪条不变量。

## 5. 测试工具 `test/test_utils.dart`

* `TestLedger.create()` — 在系统临时目录建一个**真实落盘**的账本（可注入固定时钟），
  暴露 `tempDir` / `storage` / `repository`，用 `addTearDown(ledger.dispose)` 清理。
  它用的是真的 `LedgerStorage`，所以持久化路径也被真实覆盖。
* `fixedClock()` — 固定时间（2026-03-15），供需要注入时钟的组件使用。
* `expense(...)` / `income(...)` / `transfer(...)` / `account(...)` / `category(...)`
  — 构造测试数据的语法糖。

⚠️ `TestLedger.cashId` 读的是「当前列表第一个账户」，**账户被删除后返回值会变化**。
涉及增删账户的测试请先取到局部变量再用（`repository_errors_test.dart` 里有示例）。

### 5.1 为可测性留的注入点

界面里凡是要「知道今天是哪天」的逻辑都留了可选注入参数，**生产环境不传**：

| 位置 | 参数 | 作用 |
|---|---|---|
| `TransactionEditorPage(clock:)` | `DateTime Function()?` | 记一笔页的默认发生时间 |
| `HomePage(now:)` | `DateTime Function()?` | 首页概览的「本月」 |
| `BillListPage(now:)` | `DateTime Function()?` | 账单页相对时间范围与筛选面板的基准 |
| `TransactionFilter.resolveRange({now})` / `apply(..., now:)` | `DateTime?` | 筛选规则本身 |
| `formatRelativeDay(date, {now})` | `DateTime?` | 「今天 / 昨天 / 前天」 |

另外几个常用控件留了 `Key`，因为同一个文本在页面上会合法地出现多次，
只按文本断言必然歧义：

| Key | 位置 |
|---|---|
| `HomePage.netWorthKey` / `monthIncomeKey` / `monthExpenseKey` / `monthNetKey` | 首页概览四个金额 |
| `BillListPage.quickClearKey` / `filterButtonKey` / `rangeLabelKey` / `filterBadgeKey` | 账单页筛选条 |

## 6. 写新测试时的约定

1. **优先补 `domain` 与 `data`**：这两层是逻辑所在，且测试是纯 Dart、跑得飞快。
2. **涉及磁盘的用 `TestLedger`**，不要 mock 存储；只在验证失败路径时才用
   `test/repository_errors_test.dart` 里的 `FailingStorage` 子类。
3. **断言时间时不要用 epoch**：`wallClock` 是组件语义，比较
   `year/month/day/hour/minute`；要瞬时语义请用 `occurredAtUtc`。
4. **断言 `DateTime` 相等时注意时区标记**：`DateTime(2026,3,10)` 是本地时间，
   与以 `Z` 承载的 `wallClock` 不相等，改用组件比较或 `.toUtc()`。
5. **测试里不要用 `dynamic` + `.cast()` 绕过泛型**，会让分析器的 `strict-*`
   失效；直接写 `<Transaction>[...]`。
6. **失败路径要覆盖**：`Result.isErr` 的分支、`sanitize()` 的剔除分支、
   `schemaVersion` 过高、损坏文件。
7. **尽量用界面上真实存在的定位方式**：文案、`Key`、控件类型。不要依赖
   `find.byType(Column).first` 这类脆弱的结构断言。
8. 提交前必须 `flutter analyze` 零问题、`flutter test` 全绿。

## 7. Widget 测试的必知陷阱（都是本工程踩过的）

这几条会让你花掉数小时：它们都**不报错、只是卡住或静默不生效**。

### 7.1 `testWidgets` 里真实文件 I/O **永远不完成**（最重要）

`testWidgets` 的测试体跑在 Flutter 的 **fake async** 区里。实测结论（用探针
测试确认过，不是猜测）：

* 在测试体里调用 `file.writeAsString(...)`，**文件确实会被写出来**，
  但它的 `then` / `await` 续体**永远不会被调度** —— 连 `tester.runAsync` 也救不回来。
* `pumpAndSettle()` 用的是 fake 时钟，不会给真实事件循环让路。

这三条推论决定了 widget 测试怎么写：

1. **测试编排用 `runIo`**：只有把整个操作放进 `tester.runAsync`（真实 async 区），
   仓库的 `await` 才会返回。

   ```dart
   // ❌ 会死锁（卡到 10 分钟超时，无异常、无堆栈）
   final ledger = await TestLedger.create();
   await ledger.repository.addTransaction(tx);

   // ✅ 用 test_utils.dart 的 runIo 逃出 fake async
   final ledger = (await runIo(tester, TestLedger.create))!;
   await runIo(tester, () => ledger.repository.addTransaction(tx));
   ```

2. **仓库的内存快照在 `await` 之前就已更新**，所以 `runIo` 里写完再 `pumpAndSettle`，
   界面会立刻反映新数据 —— 这正是 `home_refresh_test.dart` /
   `bills_filter_test.dart` 驱动数据变化的方式。

3. **「写完盘再改界面」的代码路径无法在 widget 测试里走完**。例如记一笔页的
   `_save()` 是 `await repository.updateTransaction(...)` **之后**才 `Navigator.pop`，
   而那个 `await` 在 fake async 区永不返回 —— 于是界面永远停在编辑页。
   这不是产品 bug，是测试环境的限制。

   因此：**不要写「点保存 → 断言页面已 pop / 首页数字已变」这类用例**，
   它在当前测试基建下必然失败。要覆盖这类契约，请改为：
   * 用 `runIo` 直接驱动仓库，断言界面刷新（见 7.1 第 2 条）；
   * 把「写盘之后要做的事」抽成不依赖 I/O 的纯函数，单独单元测试。

   > 现存用例里凡是"点了保存就断言仓库状态"的写法（例如
   > `entry_flow_test.dart`、分类保存对话框）之所以能过，是因为仓库在
   > `await` 之前就改好了内存快照；它们**没有**、也无法验证 `await` 之后的行为。

### 7.2 `tester.pageBack()` 在中文界面下静默失效

它内部靠 `find.byTooltip('Back')` 找返回按钮，而本工程是中文界面
（tooltip 为「返回」），于是它**永远找不到、返回不会发生，而且不报错** ——
后续断言只会"莫名其妙地失败"。用 `find.byType(BackButton)` 或直接
`NavigatorState.pop()`。

### 7.3 `scrollUntilVisible` 无法处理嵌套滚动区

分类编辑器里图标网格是**嵌套**滚动区。给它外层的 Scrollable 做
`scrollUntilVisible`/`dragUntilVisible` 完全无效（会一直滚到超时）。用
`tester.ensureVisible(target)`（自动处理所有祖先滚动区），或像
`scrollDownUntil` 那样逐个尝试 Scrollable。

底部弹层（`showModalBottomSheet` 的筛选面板）同理：关键词框与「应用」按钮常在
首屏之外，**直接 `tap` 会落到视口外而静默失败**，必须先 `ensureVisible`。

### 7.4 文本匹配的坑

* **`find.text` 是全等匹配，不是包含匹配**。流水行的副标题是拼出来的字符串
  （`今天 · 现金 · 便利店 · 午饭`），所以按备注查找必须用
  `find.textContaining('午饭')`，否则永远 0 命中。
* **同一个金额会合法地出现多次**：账单页的汇总条与流水行都会显示 `-¥50.00`，
  首页的净资产、本月支出与流水行也会显示同一串。按文本断言前先限定区域
  （`find.descendant(of: 列表, matching: find.text(...))`）或用 `Key`。
* **别张冠李戴按钮类型**：筛选面板里「取消」是 `OutlinedButton`、「应用」是
  `FilledButton`；分类对话框的确认是 `FilledButton`；`widgetWithText` 写错类型
  会得到 "Found 0 widgets"，看起来像功能坏了。

另外两个次要但有用的点：

* **懒构建列表里在视口外的项**：`find.x` 返回空，`ensureVisible` 会抛
  `Bad state: No element`。需要先滚动。
* **`pumpAndSettle` 会等定时器**：SnackBar 有 3 秒自动关闭定时器，可能一直等下去。
  对含 SnackBar/折叠动画的流程改用定长 `pump(Duration)`（见
  `category_customisation_test.dart` 的 `settleByPumping`）。
* **`flutter test` 的输出很大**：排查失败时用
  `--reporter expanded > log.txt` 落盘再检索，比在控制台里翻更可靠。

## 8. 自动化测试抓到过的产品缺陷

这些都不是"测试写错了"，而是测试把真实缺陷逼了出来（修在对应源码里）：

| 缺陷 | 现象 | 位置 / 修复 |
|---|---|---|
| `isUnfiltered` 基准错误 | 比较的是 `DateRangePreset.all`，而账单页默认是 `thisMonth`，于是**默认视图被判定为"有筛选"**：一进账单页就显示多余的「清除」按钮，空账本还会提示"试试放宽筛选条件" | `TransactionFilter.isUnfiltered` 改为以 `thisMonth` 为基准 |
| `activeFilterCount` 语义混乱 | 把「时间范围不是本月」也算作一个附加条件，与界面（时间范围本就有独立标签）不一致 | 只统计类型/账户/分类/关键词；时间范围由 `rangeLabel` 单独展示 |
| 自定义 chip 文案 | 筛选面板的「自定义」chip 借用了 `_draft.preset.labelWith(...)`，未选区间时显示成「本月」，与真正的「本月」chip **同名**，用户无法区分 | `labelWith` 增加 `fallback`，`filter_sheet.dart` 改为对 `DateRangePreset.custom` 求值 |

早先由 4.4 节的不变量测试抓到的归档账户净资产口径问题，也属于同一类。

## 9. 尚未覆盖的部分（已知缺口）

当前 UI 层行覆盖率 68.8%（本次补测前为低得多的水平；
`bill_list_page.dart` 96.6%、`filter_sheet.dart` 94.4%、`home_page.dart` 89.4%）。
仍有以下未自动化，建议按此顺序补：

1. 统计页：无数据、单分类、`fl_chart` 渲染不抛异常。
2. 账户页（27.1%）：新增/编辑对话框、有流水账户删除时必须二选一。
3. 设置页（36.6%）：导出对话框展示路径、导入预览文案、清空数据。
4. `app_theme.dart`（16.7%）：深浅色主题的实际渲染（多数通过默认主题覆盖）。
5. **记一笔页「返回后清掉失效分类选择」**：这条用例已写好但标记为 `skip`，
   原因是它依赖「弹窗确认 + 路由 pop + SnackBar 时序」的组合、在 widget 测试里
   不稳定（见 `category_customisation_test.dart` 对应注释）。改进方向：把
   「校验所选分类是否仍可用」抽成可注入的纯函数（如
   `categoryIsUsable(repo, id, kind)`），直接对它做单元测试，而不是通过三段
   界面交互去间接触发。
6. **「写盘成功之后」的界面动作**（保存后 pop、删除后返回）：受 7.1 第 3 条限制，
   当前无法在 widget 测试里验证，需要先把 I/O 与界面反应解耦。
7. **未覆盖的边界**：跨时区的真实迁移（改系统时区后重启）、大数据量性能
   （数万条流水）、备注/账户名里的 emoji 与超长文本。

另外，编辑器表单很长而测试窗口默认只有 800×600，**保存按钮会落在视口外**导致
`tap` 报 "Found 0 widgets"。用
`tester.binding.setSurfaceSize(const Size(800, 2400))` 放大窗口，或在 tap 前
`ensureVisible`。
