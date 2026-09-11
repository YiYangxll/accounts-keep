# 测试指南

## 1. 怎么跑

```bash
flutter analyze                                  # 期望：No issues found!
flutter test                                     # 全部用例
flutter test --coverage                          # 生成 coverage/lcov.info

# 只跑某一块
flutter test test/selectors_test.dart            # 余额与统计（最核心，改动必跑）
flutter test test/persistence_test.dart          # 落盘、损坏回退、版本校验
flutter test test/repository_errors_test.dart    # 落盘失败回滚
flutter test test/entry_flow_test.dart           # 记一笔闭环（Widget）
flutter test --plain-name "转账"                  # 按用例名筛选
```

## 2. 当前基线

| 指标 | 值 |
|---|---|
| 用例总数 | **191** |
| 行覆盖率（全工程） | 85.3% |
| `core` / `domain` / `data` / `state` | 97.5% / **94.2%** / 88.8% / 100% |
| `ui` | 58.5%（只反映 Widget 覆盖面，不作为质量指标） |

覆盖率查看（Windows 上不一定有 `lcov`，可用 PowerShell 直接汇总）：

```powershell
$lines = Get-Content coverage/lcov.info
$cur=$null; $rows=@(); $lf=0; $lh=0
foreach($l in $lines){
  if($l -like 'SF:*'){ if($cur){ $rows += [pscustomobject]@{File=$cur;LF=$lf;LH=$lh} }; $cur=($l -replace '^SF:',''); $lf=0; $lh=0 }
  elseif($l -like 'LF:*'){ $lf=[int]($l -replace '^LF:','') }
  elseif($l -like 'LH:*'){ $lh=[int]($l -replace '^LH:','') }
}
if($cur){ $rows += [pscustomobject]@{File=$cur;LF=$lf;LH=$lh} }
$th=($rows|Measure-Object LH -Sum).Sum; $tl=($rows|Measure-Object LF -Sum).Sum
"总: $th / $tl = {0:N1}%" -f (100.0*$th/$tl)
$rows | Sort-Object { $_.LH/$_.LF } | ForEach-Object { "{0,5:N0}%  {1}" -f (100.0*$_.LH/$_.LF), ($_.File -replace [regex]::Escape((Get-Location).Path+'\'),'') }
```

## 3. 测试文件分工

| 文件 | 覆盖内容 |
|---|---|
| `money_test.dart` | 分/元转换与四舍五入、容错输入、拒绝非法输入、千分位格式化、上下限 |
| `domain_test.dart` | `Transaction` 全部不变量、序列化往返、未知枚举报错、月键边界（跨年/闰月）、时区归属 |
| `domain_models_test.dart` | 三个枚举的标签/解析、`copyWith` 全字段与 `clearXxx`、各错误的文案 |
| `selectors_test.dart` | 余额（含转账与手续费）、**转账不改变净资产**、信用卡符号、月度汇总、分类聚合占比、12 月趋势、按账户汇总 |
| `filter_test.dart` | 时间区间左闭右开边界、上月/近三月/近一年/自定义、类型与账户组合、转账双向匹配、关键词（含金额两种写法）、软删除可见性 |
| `core_utils_test.dart` | `Result` 三态、`JsonX` 正常读取与**防御式报错**、日期扩展、`SettingsController` 持久化 |
| `persistence_test.dart` | 原子写入、`.bak` 生成与回退、`.corrupt-*` 留档、JSON 数字解析（`schemaVersion`）、时间以 UTC 落盘、清洗悬空引用、清空与导出 |
| `repository_test.dart` | 首次加载种子数据、流水/账户/分类 CRUD、软删除与撤销、重名拒绝、账户归档与流水迁移、分类归档 vs 删除、偏好持久化 |
| `repository_errors_test.dart` | **模拟磁盘故障**：写失败回滚内存、已有数据不丢、迁移失败保持原样、合并/替换失败 |
| `import_export_test.dart` | CSV 转义与 BOM、导出内容、JSON 往返一致、缺 `schemaVersion`/版本过高/非法 JSON 的拒绝、导入差异统计 |
| `entry_flow_test.dart` | Widget：填金额选分类保存、空金额与未选分类的拦截、转账字段切换、分类随类型过滤 |

## 4. 测试工具 `test/test_utils.dart`

* `TestLedger.create()` — 在系统临时目录建一个**真实落盘**的账本（可注入固定时钟），
  暴露 `tempDir` / `storage` / `repository`，用 `addTearDown(ledger.dispose)` 清理。
  它用的是真的 `LedgerStorage`，所以持久化路径也被真实覆盖。
* `fixedClock()` — 固定时间，供需要注入时钟的组件使用。
* `expense(...)` / `income(...)` / `transfer(...)` / `account(...)` / `category(...)`
  — 构造测试数据的语法糖。

⚠️ `TestLedger.cashId` 读的是「当前列表第一个账户」，**账户被删除后返回值会变化**。
涉及增删账户的测试请先取到局部变量再用（`repository_errors_test.dart` 里有示例）。

## 5. 写新测试时的约定

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
7. 提交前必须 `flutter analyze` 零问题、`flutter test` 全绿。

## 6. 尚未覆盖的部分（已知缺口）

以下属于 UI 层，目前只有 `entry_flow_test.dart` 的少量 Widget 测试；
如需提高 UI 覆盖率，建议按此顺序补：

1. 首页：空状态 → 记账后净资产/月汇总/最近流水刷新。
2. 账单页：筛选面板交互（切月份、关键词、清空、空状态）。
3. 统计页：无数据、单分类、`fl_chart` 渲染不抛异常。
4. 账户页：新增/编辑对话框、有流水账户删除时必须二选一。
5. 设置页：导出对话框展示路径、导入预览文案。

Widget 测试注意事项（已在 `entry_flow_test.dart` 踩过）：

* 编辑器表单很长，测试窗口默认只有 800×600，**保存按钮会落在视口外**导致
  `tap` 报 "Found 0 widgets"。用
  `tester.binding.setSurfaceSize(const Size(800, 2400))` 放大窗口，
  或在 tap 前 `ensureVisible`。
* 不要用 `pumpAndSettle` 等待「与 Widget 无关的异步仓库写盘」，
  曾出现长时间挂起；纯仓库断言请用 `test()` 而非 `testWidgets()`。
