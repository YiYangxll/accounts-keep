/// 界面格式化辅助：金额、日期与类型标签。
library;

import '../../core/date_x.dart';
import '../../core/money.dart';
import '../../domain/enums.dart';

/// 金额格式化，例如 `¥1,234.56`。
String formatMoney(int cents, {String symbol = '¥'}) =>
    Money.format(cents, symbol: symbol);

/// 带正负号的金额，例如 `+¥1,234.56` / `-¥1,234.56`。
String formatSignedMoney(int cents, {String symbol = '¥'}) {
  final String text = Money.format(cents.abs(), symbol: symbol);
  if (cents > 0) {
    return '+$text';
  }
  if (cents < 0) {
    return '-$text';
  }
  return text;
}

/// 转账金额格式化：金额 + 可选手续费。
String formatTransfer(int amountCents, int feeCents, {String symbol = '¥'}) {
  final String base = Money.format(amountCents, symbol: symbol);
  if (feeCents <= 0) {
    return base;
  }
  return '$base（手续费 ${Money.format(feeCents, symbol: symbol)}）';
}

/// 日期的中文展示，例如 `3月8日 周日`。
String formatDayHeader(DateTime date) {
  const List<String> weekdays = <String>[
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];
  final String weekday = weekdays[date.weekday - 1];
  return '${date.month}月${date.day}日 $weekday';
}

/// 日期时间展示，例如 `2026-03-08 14:05`。
String formatDateTime(DateTime date) => date.dateTimeText;

/// 交易类型对应的展示色值键（由主题层解释）。
String kindColorKey(TxKind kind) => switch (kind) {
      TxKind.expense => 'expense',
      TxKind.income => 'income',
      TxKind.transfer => 'transfer',
    };

/// 把时长描述为「今天 / 昨天 / 具体日期」。
String formatRelativeDay(DateTime date, {DateTime? now}) {
  final DateTime today = (now ?? DateTime.now()).startOfDay;
  final DateTime target = date.startOfDay;
  final int days = today.difference(target).inDays;
  if (days == 0) {
    return '今天';
  }
  if (days == 1) {
    return '昨天';
  }
  if (days == 2) {
    return '前天';
  }
  return formatDayHeader(target);
}
