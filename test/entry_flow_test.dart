/// Widget 测试：记一笔的完整闭环（选择类型/金额/分类/账户 → 保存 → 余额与净资产更新）。
library;

import 'package:accounts_keep_test/data/ledger_repository.dart';
import 'package:accounts_keep_test/domain/account.dart';
import 'package:accounts_keep_test/domain/enums.dart';
import 'package:accounts_keep_test/domain/selectors.dart';
import 'package:accounts_keep_test/state/settings_controller.dart';
import 'package:accounts_keep_test/ui/entry/transaction_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'test_utils.dart';

/// 点击「保存」按钮（并确保它在视口内）。
Future<void> tapSave(WidgetTester tester) async {
  final Finder button = find.widgetWithText(FilledButton, '保存');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
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

  Future<void> pumpEditor(WidgetTester tester) async {
    // 编辑器表单较长，给测试窗口一个足够大的高度，避免控件被移出视口。
    await tester.binding.setSurfaceSize(const Size(800, 2400));
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
          home: TransactionEditorPage(clock: fixedClock),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('记一笔支出：填金额选分类保存后流水落库且余额减少', (WidgetTester tester) async {
    await pumpEditor(tester);

    expect(find.text('记一笔'), findsOneWidget);
    expect(find.text('分类'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '12.34');
    await tester.tap(find.widgetWithText(ChoiceChip, '餐饮'));
    await tester.pumpAndSettle();

    await tapSave(tester);

    final LedgerRepository repository = ledger.repository;
    expect(repository.data.transactions.length, 1);
    expect(repository.data.transactions.single.amountCents, 1234);
    expect(repository.data.transactions.single.categoryId, isNotNull);

    final Account cash = repository.data.accounts.firstWhere(
      (Account a) => a.kind == AccountKind.cash,
    );
    expect(
      Selectors.accountBalance(cash, repository.data.transactions),
      -1234,
    );
  });

  testWidgets('金额为空时给出提示且不写入', (WidgetTester tester) async {
    await pumpEditor(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, '餐饮'));
    await tester.pumpAndSettle();
    await tapSave(tester);

    expect(find.text('请输入大于 0 的金额'), findsOneWidget);
    expect(ledger.repository.data.transactions, isEmpty);
  });

  testWidgets('未选分类时拒绝保存', (WidgetTester tester) async {
    await pumpEditor(tester);

    await tester.enterText(find.byType(TextField).first, '10');
    await tapSave(tester);

    expect(find.text('请选择分类'), findsOneWidget);
    expect(ledger.repository.data.transactions, isEmpty);
  });

  testWidgets('切换到转账后出现转入账户与手续费，且不再要求分类', (WidgetTester tester) async {
    await pumpEditor(tester);

    await tester.tap(find.text('转账'));
    await tester.pumpAndSettle();

    expect(find.text('转出账户'), findsOneWidget);
    expect(find.text('转入账户'), findsOneWidget);
    expect(find.text('手续费（可选）'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '餐饮'), findsNothing);
  });

  testWidgets('转账保存后净资产不变', (WidgetTester tester) async {
    await pumpEditor(tester);

    await tester.tap(find.text('转账'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '100');
    await tapSave(tester);

    final LedgerRepository repository = ledger.repository;
    expect(repository.data.transactions.length, 1);
    expect(
      Selectors.netWorth(
        repository.data.accounts,
        repository.data.transactions,
      ),
      0,
      reason: '账户期初均为 0，转账不改变净资产',
    );
  });

  testWidgets('分类列表随记账类型切换而变化', (WidgetTester tester) async {
    await pumpEditor(tester);

    expect(find.widgetWithText(ChoiceChip, '工资'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, '餐饮'), findsOneWidget);

    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, '工资'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '餐饮'), findsNothing);
  });
}
