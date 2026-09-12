/// Widget 测试：账单筛选交互。
///
/// 覆盖账单页的筛选链路：默认视图 → 打开筛选面板 → 勾选条件 → 应用 → 列表与
/// 汇总同步收窄 → 重置 / 清除 → 空状态兜底，以及时间预设与自定义区间。
///
/// 领域层的「筛选规则本身」（左闭右开区间、转账双向匹配、关键词匹配金额等）
/// 已由 `filter_test.dart` 纯 Dart 覆盖；本文件只测**界面接线**：
/// 面板选项是否正确写回 `_filter`、列表/徽标/汇总是否跟着变、按钮是否可用。
///
/// ⚠️ 时间固定为 [fixedClock]（2026-03-15），因此「本月」= 2026-03。真实
/// `DateTime.now()` 会让测试结论随运行日期变化，所以 `BillListPage` 支持注入
/// 时钟（生产环境不传，用系统时间）。
///
/// ⚠️ 与其它 widget 测试一致：在测试体里直接调用仓库必须用 `runIo` 包一层 ——
/// 真实文件 I/O 的完成回调在 `testWidgets` 的 fake async 区里永远不会被调度；
/// 好在仓库的内存快照在 `await` 之前就已更新，所以界面会立刻反映新数据。
library;

import 'package:accounts_keep/core/result.dart';
import 'package:accounts_keep/data/ledger_repository.dart';
import 'package:accounts_keep/data/seed_data.dart';
import 'package:accounts_keep/state/settings_controller.dart';
import 'package:accounts_keep/ui/bills/bill_list_page.dart';
import 'package:accounts_keep/ui/common/transaction_tile.dart';
import 'package:accounts_keep/ui/shell/home_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'test_utils.dart';

/// 把一个仓库写操作放到真实 async 区里执行。
Future<void> mutate(
  WidgetTester tester,
  Future<Result<Object?>> Function() action, {
  String? reason,
}) async {
  final Result<Object?>? result = await runIo(tester, action);
  expect(result!.isOk, isTrue, reason: reason ?? '仓库写操作应成功');
}

/// 「最近流水」列表区域。
Finder tilesArea() => find.byType(TransactionTile);

/// 汇总条上的笔数文本（如 `3 笔`）。
Finder countText(int n) => find.text('$n 笔');

/// 在 [area] 子树里找一段文本（避免命中汇总条上的同名金额）。
Finder textIn(Finder area, String text) =>
    find.descendant(of: area, matching: find.text(text));

/// 筛选条上的「清除」按钮（未处于默认视图时才渲染）。
Finder quickClear() => find.byKey(BillListPage.quickClearKey);

/// 筛选条上的当前区间标签。
Finder rangeLabel() => find.byKey(BillListPage.rangeLabelKey);

/// 当前区间标签的文本。
String rangeLabelText(WidgetTester tester) =>
    tester.widget<Text>(rangeLabel()).data!;

/// 筛选条件数徽标是否在展示。
bool badgeVisible(WidgetTester tester) => tester
    .widget<Badge>(find.byKey(BillListPage.filterBadgeKey))
    .isLabelVisible;

/// 点某条流水行（按金额文本定位，避免命中汇总条上的同名金额）。
Future<void> tapTileWithAmount(WidgetTester tester, String amount) async {
  final Finder target = find.ancestor(
    of: find.text(amount),
    matching: tilesArea(),
  );
  expect(target, findsOneWidget, reason: '找不到金额为 $amount 的流水行');
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// 打开筛选面板。
Future<void> openFilterSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(BillListPage.filterButtonKey));
  await tester.pumpAndSettle();
  expect(find.text('筛选'), findsOneWidget, reason: '筛选面板应已弹出');
}

/// 点面板里某个筛选项（自动先滚进视口）。
///
/// 面板是 `isScrollControlled` 的底部弹层，关键词输入框与开关常在首屏之外，
/// 直接 tap 会落到视口外而静默失败。
Future<void> tapInSheet(WidgetTester tester, Finder target) async {
  expect(target, findsOneWidget, reason: '目标控件不存在，无法点击');
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// 点「应用」并等面板收起。
Future<void> applyFilter(WidgetTester tester) async {
  final Finder apply = find.widgetWithText(FilledButton, '应用');
  await tester.ensureVisible(apply);
  await tester.pumpAndSettle();
  await tester.tap(apply);
  await tester.pumpAndSettle();
  expect(find.text('筛选'), findsNothing, reason: '应用后面板应关闭');
}

/// 把账单页挂到带 Provider 与中文本地化的 MaterialApp 下。
Future<void> pumpBills(WidgetTester tester, TestLedger ledger) async {
  // 底部弹层较高，「应用」按钮与关键词框容易落在首屏外；给足高度减少滚动。
  await tester.binding.setSurfaceSize(const Size(500, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final LedgerRepository repository = ledger.repository;
  await tester.pumpWidget(
    MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<LedgerRepository>.value(value: repository),
        ChangeNotifierProvider<SettingsController>(
          create: (BuildContext context) =>
              SettingsController(repository)..load(),
        ),
      ],
      child: const MaterialApp(
        locale: Locale('zh', 'CN'),
        localizationsDelegates: <LocalizationsDelegate<Object>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: BillListPage(now: fixedClock)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late TestLedger ledger;

  setUp(() async {
    ledger = await TestLedger.create();
  });

  tearDown(() async {
    await ledger.dispose();
  });

  /// 本月（2026-03）三条 + 上月一条 + 一条已软删除。
  ///
  /// 在测试体内用 [mutate]（= 真实 async 区）写入：`setUp` 里虽然不跑在 fake
  /// async 区、直接写也能成功，但把写入放在测试体内可以保证与界面驱动数据变化
  /// 走同一条路径，也避免依赖 setUp 的执行区间这一隐含前提。
  Future<void> seedBills(WidgetTester tester) async {
    final LedgerRepository repository = ledger.repository;
    await mutate(
      tester,
      () => repository.addTransaction(
        expense(
          id: 'tx_food',
          amountCents: 5000,
          accountId: SeedAccountIds.cash,
          categoryId: SeedCategoryIds.food,
          occurredAt: DateTime(2026, 3, 10, 12),
          payee: '便利店',
          note: '午饭',
        ),
      ),
    );
    await mutate(
      tester,
      () => repository.addTransaction(
        expense(
          id: 'tx_transport',
          amountCents: 2000,
          accountId: SeedAccountIds.debitCard,
          categoryId: SeedCategoryIds.transport,
          occurredAt: DateTime(2026, 3, 11, 12),
          note: '打车',
        ),
      ),
    );
    await mutate(
      tester,
      () => repository.addTransaction(
        income(
          id: 'tx_salary',
          amountCents: 10000,
          accountId: SeedAccountIds.debitCard,
          categoryId: SeedCategoryIds.salary,
          occurredAt: DateTime(2026, 3, 12, 12),
          note: '月薪',
        ),
      ),
    );
    await mutate(
      tester,
      () => repository.addTransaction(
        expense(
          id: 'tx_feb',
          amountCents: 4000,
          accountId: SeedAccountIds.cash,
          categoryId: SeedCategoryIds.food,
          occurredAt: DateTime(2026, 2, 20, 12),
          note: '上月的饭',
        ),
      ),
    );
    await mutate(
      tester,
      () => repository.addTransaction(
        expense(
          id: 'tx_deleted',
          amountCents: 700,
          accountId: SeedAccountIds.cash,
          categoryId: SeedCategoryIds.otherExpense,
          occurredAt: DateTime(2026, 3, 13, 12),
          note: '已删除的奶茶',
        ),
      ),
    );
    await mutate(tester, () => repository.deleteTransaction('tx_deleted'));
  }

  testWidgets('默认只显示本月，汇总条与笔数同步', (WidgetTester tester) async {
    await seedBills(tester);
    await pumpBills(tester, ledger);

    expect(find.text('本月'), findsOneWidget, reason: '筛选条应显示当前区间');
    // 本月 3 条（上月那条与已删除那条都不算）。
    expect(tilesArea(), findsNWidgets(3));
    expect(countText(3), findsOneWidget);
    expect(find.text('-¥50.00'), findsOneWidget);
    expect(find.text('-¥20.00'), findsOneWidget);
    expect(find.text('+¥100.00'), findsOneWidget);

    // 上月与已删除的都不该出现。
    expect(find.text('上月的饭'), findsNothing);
    expect(find.text('-¥40.00'), findsNothing);
    expect(find.text('已删除的奶茶'), findsNothing);

    // 没有附加条件时不显示「清除」，也没有筛选徽标。
    expect(quickClear(), findsNothing);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('勾选分类并应用后筛选生效，徽标显示条件数，清除可一键恢复', (WidgetTester tester) async {
    await seedBills(tester);
    await pumpBills(tester, ledger);

    await openFilterSheet(tester);
    await tapInSheet(tester, find.widgetWithText(FilterChip, '支出·餐饮'));
    await applyFilter(tester);

    // 只剩本月的那条餐饮支出。
    expect(tilesArea(), findsNWidgets(1));
    expect(countText(1), findsOneWidget);
    expect(textIn(tilesArea(), '-¥50.00'), findsOneWidget);
    expect(textIn(tilesArea(), '-¥20.00'), findsNothing);
    // 条件数徽标为 1（分类算一个条件）；时间范围未改，所以不出现「清除」。
    expect(badgeVisible(tester), isTrue, reason: '有额外条件时应显示筛选徽标');

    // 面板再次打开时应回显已选条件。
    await openFilterSheet(tester);
    final ChoiceChip customChip =
        tester.widget<ChoiceChip>(find.byType(ChoiceChip).last);
    expect(customChip.selected, isFalse, reason: '时间预设仍是本月的 ChoiceChip');
    expect(find.text('支出·餐饮'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.text('筛选'), findsNothing);
    expect(tilesArea(), findsNWidgets(1), reason: '取消不应改动已有筛选');

    // 一键清除回到默认视图。
    await tester.tap(quickClear());
    await tester.pumpAndSettle();
    expect(tilesArea(), findsNWidgets(3));
    expect(quickClear(), findsNothing);
  });

  testWidgets('关键词能按备注与交易对象筛选，清空按钮可撤销', (WidgetTester tester) async {
    await seedBills(tester);
    await pumpBills(tester, ledger);

    await openFilterSheet(tester);
    // 关键词在面板底部，先滚到它再输入。
    final Finder keyword = find.widgetWithText(TextField, '关键词');
    await tester.ensureVisible(keyword);
    await tester.pumpAndSettle();
    await tester.enterText(keyword, '午饭');
    await tester.pumpAndSettle();
    await applyFilter(tester);

    expect(tilesArea(), findsNWidgets(1));
    expect(find.textContaining('午饭'), findsOneWidget, reason: '命中的那条应保留');
    expect(find.textContaining('打车'), findsNothing);

    // 用输入框里的清除按钮清掉关键词。
    await openFilterSheet(tester);
    await tapInSheet(tester, find.byIcon(Icons.clear));
    await applyFilter(tester);

    expect(tilesArea(), findsNWidgets(3), reason: '清掉关键词后应恢复三笔');
  });

  testWidgets('「重置」清掉面板内的全部条件', (WidgetTester tester) async {
    await seedBills(tester);
    await pumpBills(tester, ledger);

    await openFilterSheet(tester);
    await tapInSheet(tester, find.widgetWithText(FilterChip, '支出·餐饮'));
    await tapInSheet(tester, find.widgetWithText(FilterChip, '现金'));
    await tapInSheet(tester, find.widgetWithText(TextButton, '重置'));

    // 重置后回到默认（本月、无类型/账户/分类限制）：应用应恢复三笔。
    await applyFilter(tester);
    expect(tilesArea(), findsNWidgets(3));
    expect(badgeVisible(tester), isFalse, reason: '重置后不应有筛选徽标');
  });

  testWidgets('切到「上月」后列表与区间标签都变', (WidgetTester tester) async {
    await seedBills(tester);
    await pumpBills(tester, ledger);

    await openFilterSheet(tester);
    await tapInSheet(tester, find.widgetWithText(ChoiceChip, '上月'));
    await applyFilter(tester);

    expect(rangeLabelText(tester), '上月', reason: '区间标签应切到上月');
    expect(tilesArea(), findsNWidgets(1));
    expect(find.textContaining('上月的饭'), findsOneWidget);
    expect(textIn(tilesArea(), '-¥40.00'), findsOneWidget);
    expect(find.textContaining('午饭'), findsNothing, reason: '本月的不应出现在上月视图');
    expect(quickClear(), findsOneWidget, reason: '改过时间范围后应出现一键清除');
  });

  testWidgets('类型筛选：只看转账', (WidgetTester tester) async {
    await mutate(
      tester,
      () => ledger.repository.addTransaction(
        transfer(
          id: 'tx_move',
          amountCents: 3000,
          fromAccountId: SeedAccountIds.cash,
          toAccountId: SeedAccountIds.debitCard,
          occurredAt: DateTime(2026, 3, 14, 12),
        ),
      ),
    );
    await seedBills(tester);
    await pumpBills(tester, ledger);
    expect(tilesArea(), findsNWidgets(4), reason: '本月共 4 笔（含转账）');

    await openFilterSheet(tester);
    // 类型用 FilterChip（默认全不选 = 不限），点「支出」把它排除掉之外只剩转账。
    await tapInSheet(tester, find.widgetWithText(FilterChip, '转账'));
    await applyFilter(tester);

    expect(tilesArea(), findsNWidgets(1));
    expect(find.text('现金 → 储蓄卡'), findsOneWidget);
    expect(countText(1), findsOneWidget);
  });

  testWidgets('勾选「包含已删除的记录」后软删除的流水出现', (WidgetTester tester) async {
    await seedBills(tester);
    await pumpBills(tester, ledger);
    expect(tilesArea(), findsNWidgets(3));
    expect(find.text('已删除的奶茶'), findsNothing);

    await openFilterSheet(tester);
    await tapInSheet(tester, find.text('包含已删除的记录'));
    await applyFilter(tester);

    expect(tilesArea(), findsNWidgets(4), reason: '应多出那条已删除的流水');
    expect(find.textContaining('已删除的奶茶'), findsOneWidget);
    expect(countText(4), findsOneWidget);
  });

  testWidgets('筛选结果为空时给出空状态与「清除筛选」兜底', (WidgetTester tester) async {
    await seedBills(tester);
    await pumpBills(tester, ledger);

    await openFilterSheet(tester);
    final Finder keyword = find.widgetWithText(TextField, '关键词');
    await tester.ensureVisible(keyword);
    await tester.pumpAndSettle();
    await tester.enterText(keyword, '不存在的关键字');
    await tester.pumpAndSettle();
    await applyFilter(tester);

    expect(tilesArea(), findsNothing);
    expect(find.text('没有符合条件的记录'), findsOneWidget);
    expect(find.textContaining('试试放宽筛选条件'), findsOneWidget);

    // 空状态里的「清除筛选」应能一键回到默认视图。
    await tester.tap(find.widgetWithText(OutlinedButton, '清除筛选'));
    await tester.pumpAndSettle();

    expect(tilesArea(), findsNWidgets(3));
    expect(find.text('没有符合条件的记录'), findsNothing);
  });

  testWidgets('自定义区间：选完日期后 chip 与区间标签同步变化', (WidgetTester tester) async {
    await seedBills(tester);
    await pumpBills(tester, ledger);

    await openFilterSheet(tester);
    // 「自定义」与「本月」是两颗并列的 chip，未选区间时应显示「自定义」。
    await tapInSheet(tester, find.widgetWithText(ChoiceChip, '自定义'));
    expect(find.byType(DateRangePickerDialog), findsOneWidget);

    // 区间选择器打开时定位在「今天」附近（可选上限是 now + 5 年），首屏不一定是
    // 2026-03，所以这里只验证交互链路：选两个日期 → 保存 → chip 显示区间文本
    // → 应用后筛选条的区间标签同步变化。区间过滤本身由 filter_test 覆盖。
    await tester.tap(find.text('10').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('11').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(ChoiceChip, '自定义'),
      findsNothing,
      reason: '选完区间后 chip 应显示区间文本而不是「自定义」',
    );

    await applyFilter(tester);
    final String label = rangeLabelText(tester);
    expect(
      RegExp(r'^\d{4}-\d{2}-\d{2} ~ \d{4}-\d{2}-\d{2}$').hasMatch(label),
      isTrue,
      reason: '区间标签应变成「起 ~ 止」，实际为 $label',
    );
    expect(quickClear(), findsOneWidget, reason: '自定义区间属于改过时间范围');
  });

  testWidgets('空账本且未筛选时，空状态引导去记账而不是放宽筛选', (WidgetTester tester) async {
    await pumpBills(tester, ledger);

    expect(tilesArea(), findsNothing);
    expect(find.text('没有符合条件的记录'), findsOneWidget);
    expect(
      find.textContaining('点击「记一笔」开始记账'),
      findsOneWidget,
      reason: '没有任何筛选条件时应引导去记账',
    );
    expect(find.widgetWithText(OutlinedButton, '清除筛选'), findsNothing);
    expect(countText(0), findsOneWidget);
  });

  testWidgets('在底部导航间切换时筛选状态不丢', (WidgetTester tester) async {
    await seedBills(tester);
    await tester.binding.setSurfaceSize(const Size(500, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final LedgerRepository repository = ledger.repository;
    await tester.pumpWidget(
      MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<LedgerRepository>.value(value: repository),
          ChangeNotifierProvider<SettingsController>(
            create: (BuildContext context) =>
                SettingsController(repository)..load(),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('zh', 'CN'),
          localizationsDelegates: <LocalizationsDelegate<Object>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: HomeShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('账单'));
    await tester.pumpAndSettle();
    // HomeShell 不注入时钟，用的是真实系统时间，所以这里不假设「本月」是哪个月，
    // 只要求筛选前后数量单调收窄。
    final int before = tilesArea().evaluate().length;

    await openFilterSheet(tester);
    await tapInSheet(tester, find.widgetWithText(FilterChip, '支出·餐饮'));
    await applyFilter(tester);
    expect(badgeVisible(tester), isTrue);
    expect(tilesArea().evaluate().length, lessThanOrEqualTo(before));

    // 切到「统计」再切回来：页面用 IndexedStack 保活，筛选状态不应丢。
    await tester.tap(find.text('统计'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('账单'));
    await tester.pumpAndSettle();

    expect(badgeVisible(tester), isTrue, reason: '切页回来不应丢掉筛选条件');
    expect(
      tilesArea().evaluate().length,
      lessThanOrEqualTo(before),
      reason: '切页回来筛选应仍在生效',
    );
  });
}
