/// 金额工具测试：分/元转换的精度与边界。
library;

import 'package:accounts_keep_test/core/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money.tryParseUnitsToCents', () {
    test('解析整数与小数', () {
      expect(Money.tryParseUnitsToCents('12'), 1200);
      expect(Money.tryParseUnitsToCents('12.3'), 1230);
      expect(Money.tryParseUnitsToCents('12.30'), 1230);
      expect(Money.tryParseUnitsToCents('0.01'), 1);
      expect(Money.tryParseUnitsToCents('0'), 0);
    });

    test('容忍千分位、货币符号与空白', () {
      expect(Money.tryParseUnitsToCents(' 1,234.56 '), 123456);
      expect(Money.tryParseUnitsToCents('￥12.5'), 1250);
      expect(Money.tryParseUnitsToCents('¥0.99'), 99);
      expect(Money.tryParseUnitsToCents('+8'), 800);
    });

    test('不完整但可接受的输入', () {
      expect(Money.tryParseUnitsToCents('12.'), 1200);
      expect(Money.tryParseUnitsToCents('.5'), 50);
    });

    test('超过两位小数按分四舍五入', () {
      expect(Money.tryParseUnitsToCents('1.005'), 101);
      expect(Money.tryParseUnitsToCents('1.004'), 100);
      expect(Money.tryParseUnitsToCents('0.999'), 100);
    });

    test('拒绝非法输入', () {
      expect(Money.tryParseUnitsToCents(''), isNull);
      expect(Money.tryParseUnitsToCents('   '), isNull);
      expect(Money.tryParseUnitsToCents('abc'), isNull);
      expect(Money.tryParseUnitsToCents('-5'), isNull);
      expect(Money.tryParseUnitsToCents('1.2.3'), isNull);
      expect(Money.tryParseUnitsToCents('.'), isNull);
      expect(Money.tryParseUnitsToCents('1e3'), isNull);
    });

    test('大额输入', () {
      expect(Money.tryParseUnitsToCents('99999999.99'), 9999999999);
    });
  });

  group('Money.fromUnits', () {
    test('浮点元转分四舍五入', () {
      expect(Money.fromUnits(12.345), 1235);
      expect(Money.fromUnits(12.344), 1234);
      expect(Money.fromUnits(0.005), 1);
      expect(Money.fromUnits(0), 0);
      expect(Money.fromUnits(null), 0);
    });

    test('与 toUnits 往返一致', () {
      for (final int cents in <int>[0, 1, 99, 100, 123456, 9999999999]) {
        expect(Money.fromUnits(Money.toUnits(cents)), cents);
      }
    });
  });

  group('Money 格式化', () {
    test('固定两位小数', () {
      expect(Money.toPlainString(0), '0.00');
      expect(Money.toPlainString(5), '0.05');
      expect(Money.toPlainString(1200), '12.00');
      expect(Money.toPlainString(123456), '1234.56');
    });

    test('负数金额', () {
      expect(Money.toPlainString(-123456), '-1234.56');
      expect(Money.format(-123456), '-¥1,234.56');
    });

    test('千分位分隔', () {
      expect(Money.format(0), '¥0.00');
      expect(Money.format(1200), '¥12.00');
      expect(Money.format(123456), '¥1,234.56');
      expect(Money.format(100000000), '¥1,000,000.00');
      expect(Money.format(123456, symbol: r'$'), r'$1,234.56');
    });
  });

  group('Money.isValidAmount', () {
    test('只接受正的、不超过上限的金额', () {
      expect(Money.isValidAmount(1), isTrue);
      expect(Money.isValidAmount(0), isFalse);
      expect(Money.isValidAmount(-1), isFalse);
      expect(Money.isValidAmount(Money.maxCents), isTrue);
      expect(Money.isValidAmount(Money.maxCents + 1), isFalse);
    });
  });
}
