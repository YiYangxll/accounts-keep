/// 账单筛选条件：一个不可变值对象，UI 与查询共用同一套匹配规则。
library;

import '../core/date_x.dart';
import 'enums.dart';
import 'transaction.dart';

/// 预置的快捷时间范围。
enum DateRangePreset {
  /// 本月。
  thisMonth,

  /// 上月。
  lastMonth,

  /// 近三个月（含本月）。
  lastThreeMonths,

  /// 近十二个月（含本月）。
  lastTwelveMonths,

  /// 全部时间。
  all,

  /// 自定义区间。
  custom,
}

/// 时间范围条件的展示名。
extension DateRangePresetLabel on DateRangePreset {
  /// 中文名称。
  String get label => switch (this) {
        DateRangePreset.thisMonth => '本月',
        DateRangePreset.lastMonth => '上月',
        DateRangePreset.lastThreeMonths => '近三月',
        DateRangePreset.lastTwelveMonths => '近一年',
        DateRangePreset.all => '全部',
        DateRangePreset.custom => '自定义',
      };

  /// 带自定义区间时的展示文本。
  String labelWith({DateTime? start, DateTime? endExclusive}) {
    if (this != DateRangePreset.custom ||
        start == null ||
        endExclusive == null) {
      return label;
    }
    final DateTime lastDay = endExclusive.subtract(const Duration(days: 1));
    return '${start.dateText} ~ ${lastDay.dateText}';
  }
}

/// 账单筛选条件，所有字段为 null 表示不限制。
final class TransactionFilter {
  /// 构造。
  const TransactionFilter({
    this.preset = DateRangePreset.thisMonth,
    this.customStart,
    this.customEndExclusive,
    this.kinds = const <TxKind>{},
    this.accountIds = const <String>{},
    this.categoryIds = const <String>{},
    this.keyword = '',
    this.includeDeleted = false,
  });

  /// 不施加任何条件的筛选（全部时间、全部类型）。
  static const TransactionFilter all = TransactionFilter(
    preset: DateRangePreset.all,
  );

  /// 时间范围预设。
  final DateRangePreset preset;

  /// 自定义区间起点（含）；仅 [DateRangePreset.custom] 生效。
  final DateTime? customStart;

  /// 自定义区间终点（不含）；仅 [DateRangePreset.custom] 生效。
  final DateTime? customEndExclusive;

  /// 交易类型；空集合表示不限。
  final Set<TxKind> kinds;

  /// 账户 id；空集合表示不限。转账按转出或转入账户匹配。
  final Set<String> accountIds;

  /// 分类 id；空集合表示不限。
  final Set<String> categoryIds;

  /// 关键词，匹配备注、交易对象与金额文本；空字符串表示不限。
  final String keyword;

  /// 是否包含已软删除的记录（默认不包含）。
  final bool includeDeleted;

  /// 是否设置了关键词。
  bool get hasKeyword => keyword.trim().isNotEmpty;

  /// 是否施加了类型/账户/分类限制。
  bool get hasEntityFilter =>
      kinds.isNotEmpty || accountIds.isNotEmpty || categoryIds.isNotEmpty;

  /// 是否完全无附加条件（等于「全部」视图）。
  bool get isUnfiltered =>
      preset == DateRangePreset.all && !hasKeyword && !hasEntityFilter;

  /// 已启用条件的数量，用于在界面上显示筛选徽标。
  int get activeFilterCount {
    int count = 0;
    if (preset != DateRangePreset.thisMonth) {
      count += 1;
    }
    count += kinds.length;
    if (accountIds.isNotEmpty) {
      count += 1;
    }
    if (categoryIds.isNotEmpty) {
      count += 1;
    }
    if (hasKeyword) {
      count += 1;
    }
    return count;
  }

  /// 当前时间范围的展示文本。
  String get rangeLabel =>
      preset.labelWith(start: customStart, endExclusive: customEndExclusive);

  /// 计算左闭右开的时间区间；`all` 返回 null 表示不限。
  ///
  /// [now] 用于确定「本月」，便于测试注入固定时间。
  LocalDateRange? resolveRange({DateTime? now}) {
    final DateTime today = (now ?? DateTime.now()).startOfDay;
    switch (preset) {
      case DateRangePreset.thisMonth:
        final MonthKey month = MonthKey.of(today);
        return LocalDateRange(month.firstDay, month.nextMonthFirstDay);
      case DateRangePreset.lastMonth:
        final MonthKey month = MonthKey.of(today).shift(-1);
        return LocalDateRange(month.firstDay, month.nextMonthFirstDay);
      case DateRangePreset.lastThreeMonths:
        final MonthKey month = MonthKey.of(today).shift(-2);
        return LocalDateRange(
          month.firstDay,
          MonthKey.of(today).nextMonthFirstDay,
        );
      case DateRangePreset.lastTwelveMonths:
        final MonthKey month = MonthKey.of(today).shift(-11);
        return LocalDateRange(
          month.firstDay,
          MonthKey.of(today).nextMonthFirstDay,
        );
      case DateRangePreset.all:
        return null;
      case DateRangePreset.custom:
        final DateTime? start = customStart;
        final DateTime? end = customEndExclusive;
        if (start == null || end == null) {
          return null;
        }
        return LocalDateRange(start.startOfDay, end.startOfDay);
    }
  }

  /// 判断单条交易是否满足全部条件。
  bool matches(Transaction transaction, {DateTime? now}) {
    if (transaction.isDeleted && !includeDeleted) {
      return false;
    }
    final LocalDateRange? range = resolveRange(now: now);
    if (range != null) {
      final DateTime local = transaction.wallClock;
      if (local.isBefore(range.start) || !local.isBefore(range.end)) {
        return false;
      }
    }
    if (kinds.isNotEmpty && !kinds.contains(transaction.kind)) {
      return false;
    }
    if (accountIds.isNotEmpty &&
        !accountIds.contains(transaction.accountId) &&
        !(transaction.toAccountId != null &&
            accountIds.contains(transaction.toAccountId))) {
      return false;
    }
    if (categoryIds.isNotEmpty) {
      final String? category = transaction.categoryId;
      if (category == null || !categoryIds.contains(category)) {
        return false;
      }
    }
    if (hasKeyword && !_matchesKeyword(transaction)) {
      return false;
    }
    return true;
  }

  /// 过滤一个交易列表。
  List<Transaction> apply(List<Transaction> transactions, {DateTime? now}) =>
      transactions.where((Transaction t) => matches(t, now: now)).toList();

  bool _matchesKeyword(Transaction transaction) {
    final String needle = keyword.trim().toLowerCase();
    if (needle.isEmpty) {
      return true;
    }
    bool contains(String? source) =>
        source != null && source.toLowerCase().contains(needle);
    if (contains(transaction.note) ||
        contains(transaction.payee) ||
        contains(transaction.tag)) {
      return true;
    }
    // 金额文本匹配：同时接受「12.30」与「1230」两种写法。
    final String amountText =
        (transaction.amountCents / 100).toStringAsFixed(2);
    final String compact = amountText.replaceAll('.', '');
    return amountText.contains(needle) || compact.contains(needle);
  }

  /// 复制并覆盖部分字段。
  TransactionFilter copyWith({
    DateRangePreset? preset,
    DateTime? customStart,
    DateTime? customEndExclusive,
    Set<TxKind>? kinds,
    Set<String>? accountIds,
    Set<String>? categoryIds,
    String? keyword,
    bool? includeDeleted,
  }) {
    return TransactionFilter(
      preset: preset ?? this.preset,
      customStart: customStart ?? this.customStart,
      customEndExclusive: customEndExclusive ?? this.customEndExclusive,
      kinds: kinds ?? this.kinds,
      accountIds: accountIds ?? this.accountIds,
      categoryIds: categoryIds ?? this.categoryIds,
      keyword: keyword ?? this.keyword,
      includeDeleted: includeDeleted ?? this.includeDeleted,
    );
  }

  /// 清空全部筛选条件，回到默认的「本月」。
  TransactionFilter cleared() => const TransactionFilter();

  @override
  bool operator ==(Object other) =>
      other is TransactionFilter &&
      other.preset == preset &&
      other.customStart == customStart &&
      other.customEndExclusive == customEndExclusive &&
      _setEquals(other.kinds, kinds) &&
      _setEquals(other.accountIds, accountIds) &&
      _setEquals(other.categoryIds, categoryIds) &&
      other.keyword == keyword &&
      other.includeDeleted == includeDeleted;

  @override
  int get hashCode => Object.hash(
        preset,
        customStart,
        customEndExclusive,
        Object.hashAllUnordered(kinds),
        Object.hashAllUnordered(accountIds),
        Object.hashAllUnordered(categoryIds),
        keyword,
        includeDeleted,
      );
}

/// 左闭右开的本地时间区间。
final class LocalDateRange {
  /// 构造。
  const LocalDateRange(this.start, this.end);

  /// 起点（含）。
  final DateTime start;

  /// 终点（不含）。
  final DateTime end;

  @override
  bool operator ==(Object other) =>
      other is LocalDateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '${start.dateText} ~ ${end.dateText}';
}

bool _setEquals<T>(Set<T> a, Set<T> b) {
  if (a.length != b.length) {
    return false;
  }
  return a.containsAll(b);
}
