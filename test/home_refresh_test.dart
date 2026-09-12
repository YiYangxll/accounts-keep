/// Widget 测试：首页数字刷新。
///
/// 覆盖「仓库数据变化 → 首页四个数字与最近流水跟着变」这条契约，以及跨月归属、
/// 软删除、最近流水截断、下拉刷新与净资产卡片跳转。
///
/// ⚠️ 为什么这里用 `runIo` 驱动数据变化，而不是在界面上点「保存」：
/// 本工程所有写操作都要落盘，而 `testWidgets` 的测试体跑在 fake async 区里，
/// **真实文件 I/O 的完成回调永远不会被调度**。实测（见 docs/testing.md §7）：
/// 在测试体里发起 `file.writeAsString(...)`，文件确实会被写出来，但它的
/// `then`/`await` 续体永远不执行 —— 连 `tester.runAsync` 也救不回来。
///
/// 后果是：任何「先写盘、写完再改界面」的代码路径（例如记一笔页保存成功后才
/// `Navigator.pop`）在 widget 测试里都走不到后半段。因此
/// * 仓库的**内存快照在 await 之前就已更新**，界面会立刻反映新状态；
/// * 但 `await` 之后的界面动作（pop、SnackBar）无法用普通 widget 测试验证。
///
/// 所以本文件用 `runIo` 直接驱动仓库（等价于「数据变了」），再断言首页刷新 ——
/// 这正是本文件要守住的契约。仓库写盘本身由 `repository_test.dart` 等
/// 纯 Dart 测试覆盖（那些测试不受 fake async 影响）。
///
/// ⚠️ 定位经验：首页上同一个金额文本**会合法地出现多次**（净资产、本月收入、
/// 本月支出、结余、以及最近流水里的那一条）。只按文本断言必然歧义，所以
/// `HomePage` 给这四个展示位留了固定 key，统一用 [expectSummary] 断言。
library;

import 'package:accounts_keep/core/result.dart';
import 'package:accounts_keep/data/ledger_repository.dart';
import 'package:accounts_keep/data/seed_data.dart';
import 'package:accounts_keep/domain/transaction.dart';
import 'package:accounts_keep/state/settings_controller.dart';
import 'package:accounts_keep/ui/common/transaction_tile.dart';
import 'package:accounts_keep/ui/home/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'test_utils.dart';

/// 让仓库执行一次写操作并确认成功。
///
/// 必须经由 [runIo]（真实 async 区）：在 fake async 区里直接 `await` 仓库写操作
/// 会卡死到超时。参见文件头与 `test_utils.dart` 的 `runIo` 注释。
Future<void> mutate(
  WidgetTester tester,
  Future<Result<Object?>> Function() action, {
  String? reason,
}) async {
  final Result<Object?>? result = await runIo(tester, action);
  expect(result!.isOk, isTrue, reason: reason ?? '仓库写操作应成功');
}

/// 概览卡片（净资产 + 本月收入/支出/结余）的断言助手。
///
/// 四个展示位在 `HomePage` 上有固定 key，`byKey` 既精确又能把「哪一列出错」
/// 直接写进失败信息。
void expectSummary(
  String netWorth,
  String income,
  String expense, {
  required String net,
}) {
  String textOf(Key key) {
    final Finder finder = find.byKey(key);
    expect(finder, findsOneWidget, reason: '首页应有 $key 这个展示位');
    return (finder.evaluate().single.widget as Text).data!;
  }

  expect(textOf(HomePage.netWorthKey), netWorth, reason: '净资产应刷新为 $netWorth');
  expect(textOf(HomePage.monthIncomeKey), income, reason: '本月收入应刷新为 $income');
  expect(textOf(HomePage.monthExpenseKey), expense,
      reason: '本月支出应刷新为 $expense');
  expect(textOf(HomePage.monthNetKey), net, reason: '本月结余应刷新为 $net');
}

/// 「最近流水」列表区域。
Finder tilesArea() => find.byType(TransactionTile);

/// 在 [area] 子树里找一段文本。
Finder textIn(Finder area, String text) =>
    find.descendant(of: area, matching: find.text(text));

/// 在 [area] 子树里找**包含**某段文本的控件。
///
/// 流水行的副标题是拼接出来的（`今天 · 现金 · 记录022`），所以备注只能用包含匹配。
Finder containingIn(Finder area, String text) =>
    find.descendant(of: area, matching: find.textContaining(text));

/// 把首页挂到带 Provider 与中文本地化的 MaterialApp 下。
///
/// 时间固定为 [fixedClock]（2026-03-15），因此「本月」= 2026-03，测试与真实
/// 系统日期无关。
Future<void> pumpHome(WidgetTester tester, TestLedger ledger) async {
  // 首页列表较长，给足够高度让「最近流水」里的项都真实构建出来（ListView 懒构建）。
  await tester.binding.setSurfaceSize(const Size(420, 2000));
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
        home: Scaffold(
          body: HomePage(now: fixedClock),
        ),
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

  /// 本月（固定时钟 2026-03）内的一天。
  DateTime inMonth(int day) => DateTime(2026, 3, day, 9);

  testWidgets('新增、修改、删除流水后首页四个数字与最近流水都刷新', (WidgetTester tester) async {
    await pumpHome(tester, ledger);

    // 空账本：四个数字都是 0，最近流水给出空状态。
    expectSummary('¥0.00', '¥0.00', '¥0.00', net: '¥0.00');
    expect(tilesArea(), findsNothing);
    expect(find.text('还没有记账记录'), findsOneWidget);

    // 记一笔支出 10.00。
    await mutate(
      tester,
      () => ledger.repository.addTransaction(
        expense(
          id: 'tx_1',
          amountCents: 1000,
          accountId: SeedAccountIds.cash,
          categoryId: SeedCategoryIds.food,
          occurredAt: inMonth(10),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expectSummary('-¥10.00', '¥0.00', '¥10.00', net: '-¥10.00');
    expect(textIn(tilesArea(), '-¥10.00'), findsOneWidget,
        reason: '最近流水应出现这一笔');
    expect(find.text('还没有记账记录'), findsNothing);

    // 再记一笔支出 25.50：数字必须累加。
    await mutate(
      tester,
      () => ledger.repository.addTransaction(
        expense(
          id: 'tx_2',
          amountCents: 2550,
          accountId: SeedAccountIds.cash,
          categoryId: SeedCategoryIds.transport,
          occurredAt: inMonth(11),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expectSummary('-¥35.50', '¥0.00', '¥35.50', net: '-¥35.50');
    expect(textIn(tilesArea(), '-¥25.50'), findsOneWidget);

    // 补一笔收入 100.00：收入与结余都要变，支出不变。
    await mutate(
      tester,
      () => ledger.repository.addTransaction(
        income(
          id: 'tx_3',
          amountCents: 10000,
          accountId: SeedAccountIds.cash,
          categoryId: SeedCategoryIds.salary,
          occurredAt: inMonth(12),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expectSummary('¥64.50', '¥100.00', '¥35.50', net: '¥64.50');

    // 把第一笔从 10.00 改成 30.00（在仓库层改，等价于用户在记一笔页保存）。
    final Transaction edited = ledger.repository.data.transactions
        .firstWhere((Transaction t) => t.id == 'tx_1')
        .copyWith(amountCents: 3000);
    await mutate(tester, () => ledger.repository.updateTransaction(edited));
    await tester.pumpAndSettle();

    expectSummary('¥44.50', '¥100.00', '¥55.50', net: '¥44.50');
    expect(textIn(tilesArea(), '-¥30.00'), findsOneWidget);
    expect(
      textIn(tilesArea(), '-¥10.00'),
      findsNothing,
      reason: '旧金额不应残留',
    );

    // 软删除第二笔 25.50：三个数字与流水列表都要跟着退回去。
    await mutate(tester, () => ledger.repository.deleteTransaction('tx_2'));
    await tester.pumpAndSettle();

    expectSummary('¥70.00', '¥100.00', '¥30.00', net: '¥70.00');
    expect(textIn(tilesArea(), '-¥25.50'), findsNothing, reason: '已删除的流水应消失');
    expect(tilesArea(), findsNWidgets(2));

    // 恢复后又回来。
    await mutate(tester, () => ledger.repository.restoreTransaction('tx_2'));
    await tester.pumpAndSettle();

    expectSummary('¥44.50', '¥100.00', '¥55.50', net: '¥44.50');
    expect(textIn(tilesArea(), '-¥25.50'), findsOneWidget);
    expect(tilesArea(), findsNWidgets(3));
  });

  testWidgets('本月支出与结余不计入转账，但转账只影响净资产里的账户余额', (WidgetTester tester) async {
    await pumpHome(tester, ledger);

    // 从现金转 200.00 到储蓄卡，手续费 1.00。
    await mutate(
      tester,
      () => ledger.repository.addTransaction(
        transfer(
          id: 'tx_1',
          amountCents: 20000,
          fromAccountId: SeedAccountIds.cash,
          toAccountId: SeedAccountIds.debitCard,
          occurredAt: inMonth(8),
          feeCents: 100,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 转账不进收支：收入/支出/结余都是 0；净资产只被手续费改变。
    expectSummary('-¥1.00', '¥0.00', '¥0.00', net: '¥0.00');
    expect(textIn(tilesArea(), '现金 → 储蓄卡'), findsOneWidget,
        reason: '转账也应出现在最近流水');
  });

  testWidgets('净资产含账户期初余额，且不随记账月份变化', (WidgetTester tester) async {
    await mutate(tester, () async {
      return ledger.repository.updateAccount(
        ledger.repository.data
            .accountById(SeedAccountIds.cash)!
            .copyWith(initialBalanceCents: 50000),
      );
    });
    await mutate(
      tester,
      () => ledger.repository.addTransaction(
        expense(
          id: 'tx_1',
          amountCents: 3000,
          accountId: SeedAccountIds.cash,
          categoryId: SeedCategoryIds.food,
          occurredAt: inMonth(5),
        ),
      ),
    );
    await mutate(
      tester,
      () => ledger.repository.addTransaction(
        income(
          id: 'tx_2',
          amountCents: 10000,
          accountId: SeedAccountIds.cash,
          categoryId: SeedCategoryIds.salary,
          occurredAt: inMonth(6),
        ),
      ),
    );
    // 上个月的一笔支出：仍然计入净资产（余额是累计的），但不进本月合计。
    await mutate(
      tester,
      () => ledger.repository.addTransaction(
        expense(
          id: 'tx_3',
          amountCents: 2000,
          accountId: SeedAccountIds.cash,
          categoryId: SeedCategoryIds.food,
          occurredAt: DateTime(2026, 2, 20, 9),
        ),
      ),
    );

    await pumpHome(tester, ledger);

    // 净资产 = 期初 500.00 − 30.00 + 100.00 − 20.00 = 550.00；
    // 本月：收入 100.00、支出 30.00、结余 70.00（上月那笔 20.00 不计入）。
    expectSummary('¥550.00', '¥100.00', '¥30.00', net: '¥70.00');
  });

  testWidgets('上个月的流水进「最近流水」但不计入本月合计', (WidgetTester tester) async {
    await mutate(
      tester,
      () => ledger.repository.addTransaction(
        expense(
          id: 'tx_old',
          amountCents: 4000,
          accountId: SeedAccountIds.cash,
          categoryId: SeedCategoryIds.food,
          occurredAt: DateTime(2026, 2, 20, 9),
        ),
      ),
    );
    await mutate(
      tester,
      () => ledger.repository.addTransaction(
        expense(
          id: 'tx_new',
          amountCents: 5000,
          accountId: SeedAccountIds.cash,
          categoryId: SeedCategoryIds.food,
          occurredAt: inMonth(2),
        ),
      ),
    );
    await pumpHome(tester, ledger);

    // 最近流水：本月与上月两条都在。
    expect(textIn(tilesArea(), '-¥40.00'), findsOneWidget);
    expect(textIn(tilesArea(), '-¥50.00'), findsOneWidget);
    expect(find.text('餐饮'), findsNWidgets(2), reason: '两条都应出现在最近流水里');
    // 净资产是累计的（两条都算），本月合计只算本月那一条。
    expectSummary('-¥90.00', '¥0.00', '¥50.00', net: '-¥50.00');
  });

  testWidgets('最近流水最多 20 条，且按时间倒序', (WidgetTester tester) async {
    for (int i = 0; i < 22; i++) {
      await mutate(
        tester,
        () => ledger.repository.addTransaction(
          expense(
            id: 'tx_${i.toString().padLeft(2, '0')}',
            amountCents: 1000 + i,
            accountId: SeedAccountIds.cash,
            categoryId: SeedCategoryIds.food,
            occurredAt: DateTime(2026, 3, 1, 9).add(Duration(minutes: i)),
            note: '记录${(i + 1).toString().padLeft(3, '0')}',
          ),
        ),
      );
    }
    await pumpHome(tester, ledger);

    expect(tilesArea(), findsNWidgets(20), reason: '最近流水只展示 20 条');
    expect(
      textIn(tilesArea(), '记录022'),
      findsNothing,
      reason: '备注在副标题里被拼接，精确匹配本来就不该命中（防呆）',
    );
    expect(containingIn(tilesArea(), '记录022'), findsOneWidget,
        reason: '最新一条在列表里');
    expect(containingIn(tilesArea(), '记录003'), findsOneWidget,
        reason: '倒数第 20 条是分界');
    expect(containingIn(tilesArea(), '记录002'), findsNothing,
        reason: '第 21 条应被截断');
    expect(containingIn(tilesArea(), '记录001'), findsNothing,
        reason: '第 22 条应被截断');
  });

  testWidgets('下拉刷新不会破坏首页（RefreshIndicator 能正常走完）',
      (WidgetTester tester) async {
    await pumpHome(tester, ledger);

    expect(find.text('还没有记账记录'), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);

    await tester.fling(find.byType(ListView), const Offset(0, 320), 1000);
    await tester.pumpAndSettle();

    expect(find.text('还没有记账记录'), findsOneWidget, reason: '刷新后仍应是空账本状态');
  });

  testWidgets('点净资产卡片能进入账户页', (WidgetTester tester) async {
    await pumpHome(tester, ledger);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(find.text('账户'), findsOneWidget, reason: '应进入账户页');
  });
}
