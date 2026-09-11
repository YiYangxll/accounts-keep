/// 日期工具：统一「月键」与本地时区安全的月份边界计算。
///
/// 约定：
/// * 交易时间以本地时间保存，并额外保存写入时的 UTC 偏移，保证设备时区变更后
///   历史账目的日期与月份归属不漂移。
/// * 月份键统一为 `yyyy-MM` 字符串，便于持久化与排序。
library;

/// 月键（`yyyy-MM`），不可变值对象，按时间先后可比较。
final class MonthKey implements Comparable<MonthKey> {
  const MonthKey(this.year, this.month)
      : assert(month >= 1 && month <= 12, '月份必须在 1-12 之间');

  /// 从日期构造。
  factory MonthKey.of(DateTime date) => MonthKey(date.year, date.month);

  /// 解析 `yyyy-MM`，失败返回 null。
  static MonthKey? tryParse(String text) {
    final RegExpMatch? match =
        RegExp(r'^(\d{4})-(\d{2})$').firstMatch(text.trim());
    if (match == null) {
      return null;
    }
    final int? year = int.tryParse(match.group(1)!);
    final int? month = int.tryParse(match.group(2)!);
    if (year == null || month == null || month < 1 || month > 12) {
      return null;
    }
    return MonthKey(year, month);
  }

  /// 年。
  final int year;

  /// 月（1-12）。
  final int month;

  /// 月份序号，便于差值计算。
  int get ordinal => year * 12 + (month - 1);

  /// 该月第一天（本地时间零点）。
  DateTime get firstDay => DateTime(year, month);

  /// 该月最后一天（本地时间零点）。
  DateTime get lastDay => DateTime(year, month + 1, 0);

  /// 该月下一月的第一天（用作左闭右开区间的上界）。
  DateTime get nextMonthFirstDay => DateTime(year, month + 1);

  /// 判断某日期是否属于该月。
  bool contains(DateTime date) => date.year == year && date.month == month;

  /// 根据月份序号还原月键。
  static MonthKey fromOrdinal(int ordinal) =>
      MonthKey(ordinal ~/ 12, ordinal % 12 + 1);

  /// 前后平移若干月，返回新月键。
  MonthKey shift(int months) => fromOrdinal(ordinal + months);

  /// 展示文本，例如 `2026年3月`。
  String get label => '$year年$month月';

  /// 持久化文本 `yyyy-MM`。
  @override
  String toString() => '$year-${month.toString().padLeft(2, '0')}';

  @override
  int compareTo(MonthKey other) => ordinal.compareTo(other.ordinal);

  @override
  bool operator ==(Object other) =>
      other is MonthKey && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

/// 本地日期与时间辅助。
extension DateTimeX on DateTime {
  /// 取当天零点（本地时区）。
  DateTime get startOfDay => DateTime(year, month, day);

  /// 取下周一的零点，用作「本周」区间的上界。
  DateTime get nextWeekStart => startOfDay.add(const Duration(days: 7));

  /// 所属月键。
  MonthKey get monthKey => MonthKey.of(this);

  /// 是否与另一日期同一天（忽略时间部分）。
  bool isSameDay(DateTime other) =>
      year == other.year && month == other.month && day == other.day;

  /// 是否与另一日期同月（忽略时间部分）。
  bool isSameMonth(DateTime other) =>
      year == other.year && month == other.month;

  /// `yyyy-MM-dd` 文本。
  String get dateText => '$year-${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  /// `yyyy-MM-dd HH:mm` 文本。
  String get dateTimeText => '$dateText ${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}';

  /// UTC 与本地时间的偏移分钟数，用于持久化时区信息。
  int get offsetMinutes => timeZoneOffset.inMinutes;
}
