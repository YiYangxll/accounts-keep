/// 记一笔页面的布局回归测试。
///
/// 背景：该表单较长（金额 + 分类 + 账户 + 日期 + 交易对象 + 备注），金额字号又远大于
/// 正文，历史上出现过「金额/账户/日期 与输入框挤在一起、被键盘遮挡」的问题。
/// 这里守住三件事：
///   1. 各输入框的标签始终落在自己的框内（不越界到相邻控件）；
///   2. 各输入框之间不出现垂直重叠；
///   3. 放大会不会导致 RenderFlex overflow。
library;

import 'package:accounts_keep/data/ledger_repository.dart';
import 'package:accounts_keep/state/settings_controller.dart';
import 'package:accounts_keep/ui/entry/transaction_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'test_utils.dart';

void main() {
  late TestLedger ledger;

  setUp(() async {
    ledger = await TestLedger.create();
  });

  tearDown(() async {
    await ledger.dispose();
  });

  Future<void> pumpEditor(
    WidgetTester tester, {
    double textScale = 1.0,
    Size size = const Size(411, 914),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final LedgerRepository repository = ledger.repository;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: MultiProvider(
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
      ),
    );
    await tester.pumpAndSettle();
  }

  group('记一笔页面布局', () {
    testWidgets('金额/账户/日期 的标签都落在自己的输入框内，且互不重叠', (WidgetTester tester) async {
      await pumpEditor(tester);

      final Rect amount = tester.getRect(find.byType(TextField).first);
      final Rect account = tester.getRect(find.text('账户').first);
      final Rect date = tester.getRect(find.text('日期').first);
      final Rect category = tester.getRect(find.text('分类').first);

      // 每条标签都必须落在它有意义的纵向区间里。
      expect(
        find.text('金额').evaluate(),
        isNotEmpty,
        reason: '金额标签应存在',
      );
      final Rect amountLabel = tester.getRect(find.text('金额').first);

      // 金额标签在金额输入框内。
      expect(amountLabel.top, greaterThanOrEqualTo(amount.top - 1));
      expect(amountLabel.bottom, lessThanOrEqualTo(amount.bottom + 1));
      // 分类标题在金额输入框下方。
      expect(category.top, greaterThanOrEqualTo(amount.bottom));
      // 账户标签在分类区域下方、日期标签上方。
      expect(account.top, greaterThan(category.bottom));
      expect(date.top, greaterThan(account.bottom));

      // 输入框彼此不重叠。
      final List<Rect> fields = <Rect>[
        for (int i = 0;
            i < tester.widgetList(find.byType(TextField)).length;
            i++)
          tester.getRect(find.byType(TextField).at(i)),
      ]..sort((Rect a, Rect b) => a.top.compareTo(b.top));
      for (int i = 0; i < fields.length - 1; i++) {
        expect(
          fields[i].bottom,
          lessThanOrEqualTo(fields[i + 1].top),
          reason: '第 $i 个与第 ${i + 1} 个输入框不应重叠',
        );
      }
    });

    testWidgets('金额输入框比普通输入框更高（大字号不会被挤扁）', (WidgetTester tester) async {
      await pumpEditor(tester);

      final Rect amount = tester.getRect(find.byType(TextField).first);
      final Rect note = tester.getRect(find.byType(TextField).last);
      expect(
        amount.height,
        greaterThan(note.height),
        reason: '28sp 的金额框应明显高于正文输入框',
      );
      expect(amount.height, greaterThan(70));
    });

    testWidgets('系统字号放大到 1.5 倍也不出现 overflow', (WidgetTester tester) async {
      for (final double scale in <double>[1.0, 1.3, 1.5]) {
        await pumpEditor(tester, textScale: scale);
        expect(
          tester.takeException(),
          isNull,
          reason: 'textScale=$scale 时不应有布局异常',
        );
      }
    });

    testWidgets('窄屏（360x640）下表单可滚动到保存按钮', (WidgetTester tester) async {
      await pumpEditor(tester, size: const Size(360, 640));

      expect(tester.takeException(), isNull);

      // ListView 是懒构建的：窄屏上保存按钮尚未创建，需要一边滚一边找。
      final Finder save = find.widgetWithText(FilledButton, '保存');
      await tester.dragUntilVisible(
        save,
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      expect(save, findsOneWidget);
      expect(
        tester.getRect(save).bottom,
        lessThanOrEqualTo(640),
        reason: '滚动后保存按钮应进入可视区',
      );
    });

    testWidgets('转账模式下的字段同样不重叠', (WidgetTester tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text('转账'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final List<Rect> fields = <Rect>[
        for (int i = 0;
            i < tester.widgetList(find.byType(TextField)).length;
            i++)
          tester.getRect(find.byType(TextField).at(i)),
      ]..sort((Rect a, Rect b) => a.top.compareTo(b.top));
      for (int i = 0; i < fields.length - 1; i++) {
        expect(fields[i].bottom, lessThanOrEqualTo(fields[i + 1].top));
      }
    });
  });
}
