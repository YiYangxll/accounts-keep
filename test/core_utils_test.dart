/// 核心工具补充测试：Result、JSON 防御式解析、日期扩展与偏好控制器。
library;

import 'package:accounts_keep/core/date_x.dart';
import 'package:accounts_keep/core/json_x.dart';
import 'package:accounts_keep/core/result.dart';
import 'package:accounts_keep/domain/enums.dart';
import 'package:accounts_keep/domain/ledger_error.dart';
import 'package:accounts_keep/state/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

void main() {
  group('Result', () {
    test('成功态', () {
      const Result<int> ok = Result<int>.ok(7);
      expect(ok.isOk, isTrue);
      expect(ok.isErr, isFalse);
      expect(ok.value, 7);
      expect(ok.error, isNull);
      expect(ok.getOrElse(0), 7);
      expect(ok.toString(), contains('7'));
    });

    test('失败态', () {
      const Result<int> err = Result<int>.err(InvalidAmountError(0));
      expect(err.isErr, isTrue);
      expect(err.error, isA<InvalidAmountError>());
      expect(err.getOrElse(42), 42);
      expect(err.toString(), contains('InvalidAmountError'));
      expect(() => err.value, throwsStateError);
    });

    test('map 与 flatMap', () {
      const Result<int> ok = Result<int>.ok(4);
      expect(ok.map((int v) => v * 2).value, 8);
      expect(ok.flatMap((int v) => Result<int>.ok(v + 1)).value, 5);

      const Result<int> err = Result<int>.err(EmptyNameError());
      expect(err.map((int v) => v * 2).isErr, isTrue);
      expect(err.flatMap((int v) => Result<int>.ok(v)).isErr, isTrue);
      expect(err.map((int v) => v).error, isA<EmptyNameError>());
    });

    test('Unit 标记', () {
      const Unit unit = Unit();
      expect(unit.toString(), 'Unit');
      expect(unit, isA<Unit>());
    });
  });

  group('JsonX 正常读取', () {
    final Map<String, Object?> json = <String, Object?>{
      'text': '值',
      'empty': '',
      'number': 12,
      'double': 3.0,
      'flag': true,
      'map': <String, Object?>{'inner': 1},
      'list': <Object?>[
        <String, Object?>{'id': 'x'},
      ],
      'stamp': '2026-03-10T04:30:00.000Z',
      'nullValue': null,
    };

    test('字符串', () {
      expect(json.requireString('text'), '值');
      expect(json.optionalString('empty'), isNull);
      expect(json.optionalString('nullValue'), isNull);
      expect(json.optionalString('text'), '值');
    });

    test('整数（兼容 JSON 的 double）', () {
      expect(json.requireInt('number'), 12);
      expect(json.requireInt('double'), 3);
      expect(json.optionalInt('nullValue'), isNull);
      expect(json.optionalInt('number'), 12);
    });

    test('布尔、Map 与 List', () {
      expect(json.requireBool('flag'), isTrue);
      expect(json.requireMap('map')['inner'], 1);
      expect(json.optionalMap('map')!['inner'], 1);
      expect(json.optionalMap('nullValue'), isNull);
      expect(json.optionalList('list').length, 1);
      expect(json.optionalList('nullValue'), isEmpty);
    });

    test('时间', () {
      expect(json.requireDateTime('stamp'), DateTime.utc(2026, 3, 10, 4, 30));
      expect(json.optionalDateTime('nullValue'), isNull);
    });

    test('对象数组解析', () {
      final List<Map<String, Object?>> parsed =
          parseObjectList<Map<String, Object?>>(
        json.optionalList('list'),
        (Map<String, Object?> item) => item,
      );
      expect(parsed.single['id'], 'x');
    });
  });

  group('JsonX 防御式报错', () {
    final Map<String, Object?> json = <String, Object?>{
      'number': 'not a number',
      'badDouble': 1.5,
      'badBool': 'yes',
      'badMap': 3,
      'badList': 'nope',
      'badStamp': 'not a date',
      'quotedMap': <Object?, Object?>{'k': 'v'},
      'quotedInner': <Object?, Object?>{
        'inner': <Object?, Object?>{'a': 1}
      },
    };

    void expectCorrupt(void Function() action) {
      expect(action, throwsA(isA<CorruptDataError>()));
    }

    test('类型不符时报错', () {
      // 字符串字段拿到字符串是合法的，不会报错。
      expect(json.requireString('number'), 'not a number');
      expectCorrupt(() => json.requireString('badMap'));
      expectCorrupt(() => json.requireInt('number'));
      expectCorrupt(() => json.requireInt('badDouble'));
      expectCorrupt(() => json.requireBool('badBool'));
      expectCorrupt(() => json.requireMap('badMap'));
      expectCorrupt(() => json.requireList('badList'));
      expectCorrupt(() => json.requireDateTime('badStamp'));
      expectCorrupt(() => json.requireString('missing'));
      expectCorrupt(() => json.requireInt('missing'));
      expectCorrupt(() => json.requireBool('missing'));
      expectCorrupt(() => json.requireMap('missing'));
      expectCorrupt(() => json.requireList('missing'));
      expectCorrupt(() => json.requireDateTime('missing'));
      expectCorrupt(() => json.optionalString('badMap'));
      expectCorrupt(() => json.optionalInt('number'));
      expectCorrupt(() => json.optionalMap('badMap'));
      expectCorrupt(() => json.optionalList('badList'));
      expectCorrupt(() => json.optionalDateTime('badStamp'));
    });

    test('空字符串视为缺失而不是损坏', () {
      final Map<String, Object?> blank = <String, Object?>{
        'text': '',
        'stamp': '',
      };
      expect(blank.optionalString('text'), isNull);
      expect(blank.optionalDateTime('stamp'), isNull);
    });

    test('Object 键的 Map 也能归一化', () {
      expect(json.requireMap('quotedMap')['k'], 'v');
      final Map<String, Object?> nested = json.requireMap('quotedInner');
      expect(nested['inner'], isA<Map<Object?, Object?>>());
    });

    test('数组元素不是对象时报错', () {
      expectCorrupt(
        () => parseObjectList<int>(
          <Object?>[1, 2],
          (Map<String, Object?> item) => 0,
        ),
      );
    });
  });

  group('日期扩展', () {
    test('当天零点与下周起点', () {
      final DateTime dt = DateTime(2026, 3, 10, 15, 45, 30);
      expect(dt.startOfDay, DateTime(2026, 3, 10));
      expect(dt.nextWeekStart, DateTime(2026, 3, 17));
    });

    test('月键与同月判断', () {
      final DateTime dt = DateTime(2026, 3, 10);
      expect(dt.monthKey, const MonthKey(2026, 3));
      expect(dt.isSameMonth(DateTime(2026, 3, 31)), isTrue);
      expect(dt.isSameMonth(DateTime(2026, 4, 1)), isFalse);
    });

    test('时区偏移可达取', () {
      final DateTime dt = DateTime(2026, 3, 10, 12);
      expect(dt.offsetMinutes, dt.timeZoneOffset.inMinutes);
    });
  });

  group('SettingsController', () {
    late TestLedger ledger;

    setUp(() async {
      ledger = await TestLedger.create();
    });

    tearDown(() async {
      await ledger.dispose();
    });

    test('默认偏好', () {
      final SettingsController controller =
          SettingsController(ledger.repository);
      expect(controller.themeMode, AppThemeMode.system);
      expect(controller.currencySymbol, '¥');
    });

    test('设置并持久化主题模式', () async {
      final SettingsController controller =
          SettingsController(ledger.repository);
      final Result<Unit> saved =
          await controller.setThemeMode(AppThemeMode.dark);
      expect(saved.isOk, isTrue);
      expect(controller.themeMode, AppThemeMode.dark);
      expect(
        ledger.repository.preference(PreferenceKeys.themeMode),
        'dark',
      );

      // 重新构建控制器时应从账本读回。
      final SettingsController reloaded = SettingsController(ledger.repository)
        ..load();
      expect(reloaded.themeMode, AppThemeMode.dark);
    });

    test('设置并持久化货币符号', () async {
      final SettingsController controller =
          SettingsController(ledger.repository);
      final Result<Unit> saved = await controller.setCurrencySymbol(r'$');
      expect(saved.isOk, isTrue);
      expect(controller.currencySymbol, r'$');

      final SettingsController reloaded = SettingsController(ledger.repository)
        ..load();
      expect(reloaded.currencySymbol, r'$');
    });

    test('主题模式映射到 Flutter ThemeMode', () {
      expect(AppThemeMode.system.themeMode.name, 'system');
      expect(AppThemeMode.light.themeMode.name, 'light');
      expect(AppThemeMode.dark.themeMode.name, 'dark');
      expect(AppThemeMode.system.label, '跟随系统');
      expect(AppThemeMode.light.label, '浅色');
      expect(AppThemeMode.dark.label, '深色');
      expect(AppThemeModeLabel.fromStorage('light'), AppThemeMode.light);
      expect(AppThemeModeLabel.fromStorage('unknown'), AppThemeMode.system);
      expect(AppThemeModeLabel.fromStorage(null), AppThemeMode.system);
    });

    test('通知监听者', () async {
      final SettingsController controller =
          SettingsController(ledger.repository);
      int notified = 0;
      controller.addListener(() => notified++);
      await controller.setThemeMode(AppThemeMode.light);
      await controller.setCurrencySymbol('€');
      controller.load();
      expect(notified, 3);
    });

    test('分类类型与账户类型可被 UI 用于筛选标签', () {
      expect(CategoryKind.expense.label, TxKind.expense.label);
      expect(CategoryKind.income.label, TxKind.income.label);
    });
  });
}
