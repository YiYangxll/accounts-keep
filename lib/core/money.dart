/// 金额工具：全项目统一以「分」为最小单位，避免浮点误差。
///
/// 约定：
/// * 领域层与持久化层只使用整数分（int）。
/// * 仅在 UI 输入/展示边界做元与分的转换。
/// * 金额一律为非负整数，正负语义由交易类型（收入/支出）表达。
library;

/// 金额转换与格式化。
abstract final class Money {
  /// 一元的分数。
  static const int centsPerUnit = 100;

  /// 一分等于的元数。
  static const double unitsPerCent = 0.01;

  /// 单笔金额上限（1 亿元），防止误输入与溢出。
  static const int maxCents = 100000000 * centsPerUnit;

  /// 把分转成用于展示的元（double，仅用于图表等数值计算）。
  static double toUnits(int cents) => cents / centsPerUnit;

  /// 把元转成分，四舍五入到分。入参为 null 时返回 0。
  static int fromUnits(double? units) {
    if (units == null) {
      return 0;
    }
    return (units * centsPerUnit).round();
  }

  /// 解析用户输入的金额字符串，成功返回分，失败返回 null。
  ///
  /// 接受形如 `12`、`12.3`、`12.30`、`0.01`、`1,234.56`、`￥12.5`、`12.` 的输入，
  /// 超过两位小数按分四舍五入，不接受负数与科学计数法。
  static int? tryParseUnitsToCents(String raw) {
    var text = raw.trim();
    if (text.isEmpty) {
      return null;
    }
    // 去掉常见货币符号与千分位分隔符。
    text = text.replaceAll(RegExp(r'[,\s￥¥]'), '');
    if (text.startsWith('+')) {
      text = text.substring(1);
    }
    if (text.isEmpty || text.contains('-')) {
      return null;
    }
    if (!RegExp(r'^\d*\.?\d*$').hasMatch(text)) {
      return null;
    }
    // `12.` 与 `.5` 都是合法输入。
    final bool hasDigits = text.replaceAll('.', '').isNotEmpty;
    if (!hasDigits) {
      return null;
    }
    final int dotIndex = text.indexOf('.');
    if (dotIndex < 0) {
      final int? whole = int.tryParse(text);
      return whole == null ? null : whole * centsPerUnit;
    }
    final String intPart = text.substring(0, dotIndex);
    final String fracPart = text.substring(dotIndex + 1);
    final int? whole = intPart.isEmpty ? 0 : int.tryParse(intPart);
    if (whole == null) {
      return null;
    }
    // 保留三位以便对第三位做四舍五入。
    final String padded = fracPart.padRight(3, '0');
    final int? firstTwo = int.tryParse(padded.substring(0, 2));
    final int? third = int.tryParse(padded.substring(2, 3));
    if (firstTwo == null || third == null) {
      return null;
    }
    final int roundUp = third >= 5 ? 1 : 0;
    return whole * centsPerUnit + firstTwo + roundUp;
  }

  /// 原始元展示文本（不带货币符号、不带千分位），固定两位小数。
  ///
  /// 例如 `1234.5` 元 → `1234.50`，`-1234.5` 元 → `-1234.50`（用于「待还款」等）。
  static String toPlainString(int cents) {
    final String sign = cents < 0 ? '-' : '';
    final int abs = cents.abs();
    final int whole = abs ~/ centsPerUnit;
    final int frac = abs % centsPerUnit;
    return '$sign$whole.${frac.toString().padLeft(2, '0')}';
  }

  /// 带千分位的展示文本，例如 `¥1,234.56`。
  static String format(int cents, {String symbol = '¥'}) {
    final String plain = toPlainString(cents);
    final bool negative = plain.startsWith('-');
    final String body = negative ? plain.substring(1) : plain;
    final int dotIndex = body.indexOf('.');
    final String whole = body.substring(0, dotIndex);
    final String frac = body.substring(dotIndex + 1);
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(whole[i]);
    }
    return '${negative ? '-' : ''}$symbol$buffer.$frac';
  }

  /// 校验金额是否为合法的正整数分且不超过上限。
  static bool isValidAmount(int cents) => cents > 0 && cents <= maxCents;
}
