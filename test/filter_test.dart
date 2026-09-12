/// 账单筛选条件测试：时间边界、组合条件与关键词。
library;

import 'package:accounts_keep/domain/enums.dart';
import 'package:accounts_keep/domain/transaction.dart';
import 'package:accounts_keep/domain/transaction_filter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

void main() {
  final DateTime now = DateTime(2026, 3, 15, 12);

  final Transaction marchFood = expense(
    id: 'e1',
    amountCents: 12345,
    accountId: 'cash',
    categoryId: 'food',
    occurredAt: DateTime(2026, 3, 10, 12),
    note: '和客户吃饭',
    payee: '海底捞',
  );
  final Transaction marchTransfer = transfer(
    id: 't1',
    amountCents: 50000,
    fromAccountId: 'cash',
    toAccountId: 'bank',
    occurredAt: DateTime(2026, 3, 12, 9),
  );
  final Transaction febFood = expense(
    id: 'e2',
    amountCents: 3000,
    accountId: 'bank',
    categoryId: 'food',
    occurredAt: DateTime(2026, 2, 20, 12),
    note: '早餐',
  );
  final Transaction monthStart = expense(
    id: 'e3',
    amountCents: 100,
    accountId: 'cash',
    categoryId: 'food',
    // 3 月 1 日 00:00 必须属于本月
    occurredAt: DateTime(2026, 3, 1),
  );
  final Transaction nextMonthStart = expense(
    id: 'e4',
    amountCents: 200,
    accountId: 'cash',
    categoryId: 'food',
    // 4 月 1 日 00:00 必须不属于本月
    occurredAt: DateTime(2026, 4, 1),
  );
  final Transaction deleted = expense(
    id: 'e5',
    amountCents: 999,
    accountId: 'cash',
    categoryId: 'food',
    occurredAt: DateTime(2026, 3, 5, 12),
  ).copyWith(deletedAtUtc: DateTime.utc(2026, 3, 6));

  final List<Transaction> all = <Transaction>[
    marchFood,
    marchTransfer,
    febFood,
    monthStart,
    nextMonthStart,
    deleted,
  ];

  group('时间范围', () {
    test('本月为左闭右开区间', () {
      const TransactionFilter filter = TransactionFilter();
      final List<Transaction> result = filter.apply(all, now: now);
      final Set<String> ids = result.map((Transaction t) => t.id).toSet();
      expect(ids, containsAll(<String>['e1', 't1', 'e3']));
      expect(ids, isNot(contains('e2')), reason: '上月记录不应出现');
      expect(ids, isNot(contains('e4')), reason: '下月月初记录不应出现');
    });

    test('上月范围', () {
      const TransactionFilter filter = TransactionFilter(
        preset: DateRangePreset.lastMonth,
      );
      final List<Transaction> result = filter.apply(all, now: now);
      expect(result.map((Transaction t) => t.id), <String>['e2']);
    });

    test('近三月包含本月在内共三个月', () {
      const TransactionFilter filter = TransactionFilter(
        preset: DateRangePreset.lastThreeMonths,
      );
      final LocalDateRange? range = filter.resolveRange(now: now);
      expect(range, isNotNull);
      expect(range!.start, DateTime(2026, 1, 1));
      expect(range.end, DateTime(2026, 4, 1));
    });

    test('近一年跨年正确', () {
      const TransactionFilter filter = TransactionFilter(
        preset: DateRangePreset.lastTwelveMonths,
      );
      final LocalDateRange range = filter.resolveRange(now: now)!;
      expect(range.start, DateTime(2025, 4, 1));
      expect(range.end, DateTime(2026, 4, 1));
    });

    test('全部时间不限制范围', () {
      expect(
        const TransactionFilter(preset: DateRangePreset.all).resolveRange(),
        isNull,
      );
      expect(
        TransactionFilter.all.apply(all, now: now).length,
        5,
        reason: '默认不含已删除记录，共 5 条',
      );
    });

    test('自定义区间缺失端点时退化为不限', () {
      const TransactionFilter filter = TransactionFilter(
        preset: DateRangePreset.custom,
      );
      expect(filter.resolveRange(now: now), isNull);
    });

    test('自定义区间生效', () {
      final TransactionFilter filter = TransactionFilter(
        preset: DateRangePreset.custom,
        customStart: DateTime(2026, 3, 10),
        customEndExclusive: DateTime(2026, 3, 13),
      );
      final List<Transaction> result = filter.apply(all, now: now);
      expect(
        result.map((Transaction t) => t.id).toSet(),
        <String>{'e1', 't1'},
      );
    });
  });

  group('类型与账户', () {
    test('按类型筛选', () {
      const TransactionFilter filter = TransactionFilter(
        preset: DateRangePreset.all,
        kinds: <TxKind>{TxKind.transfer},
      );
      expect(
        filter.apply(all, now: now).map((Transaction t) => t.id),
        <String>['t1'],
      );
    });

    test('转账按转出或转入账户都能匹配', () {
      const TransactionFilter byTarget = TransactionFilter(
        preset: DateRangePreset.all,
        accountIds: <String>{'bank'},
      );
      final Set<String> ids =
          byTarget.apply(all, now: now).map((Transaction t) => t.id).toSet();
      expect(ids, contains('t1'));
      expect(ids, contains('e2'));
    });

    test('按分类筛选时转账被排除', () {
      const TransactionFilter filter = TransactionFilter(
        preset: DateRangePreset.all,
        categoryIds: <String>{'food'},
      );
      expect(
        filter.apply(all, now: now).map((Transaction t) => t.id).toSet(),
        <String>{'e1', 'e2', 'e3', 'e4'},
      );
    });
  });

  group('关键词与软删除', () {
    test('匹配备注与交易对象', () {
      const TransactionFilter byNote = TransactionFilter(
        preset: DateRangePreset.all,
        keyword: '客户',
      );
      expect(byNote.apply(all, now: now).single.id, 'e1');

      const TransactionFilter byPayee = TransactionFilter(
        preset: DateRangePreset.all,
        keyword: '海底',
      );
      expect(byPayee.apply(all, now: now).single.id, 'e1');
    });

    test('匹配金额文本的两种写法', () {
      const TransactionFilter decimal = TransactionFilter(
        preset: DateRangePreset.all,
        keyword: '123.45',
      );
      expect(decimal.apply(all, now: now).single.id, 'e1');

      const TransactionFilter compact = TransactionFilter(
        preset: DateRangePreset.all,
        keyword: '12345',
      );
      expect(compact.apply(all, now: now).single.id, 'e1');
    });

    test('关键词无匹配时返回空', () {
      const TransactionFilter filter = TransactionFilter(
        preset: DateRangePreset.all,
        keyword: '不存在的词',
      );
      expect(filter.apply(all, now: now), isEmpty);
    });

    test('默认排除软删除，可显式包含', () {
      const TransactionFilter without =
          TransactionFilter(preset: DateRangePreset.all);
      expect(
        without.apply(all, now: now).map((Transaction t) => t.id),
        isNot(contains('e5')),
      );

      const TransactionFilter withDeleted = TransactionFilter(
        preset: DateRangePreset.all,
        includeDeleted: true,
      );
      expect(
        withDeleted.apply(all, now: now).map((Transaction t) => t.id),
        contains('e5'),
      );
    });
  });

  group('条件计数与副本', () {
    test('activeFilterCount 只统计用户额外附加的条件', () {
      // 默认视图（本月、无附加条件）不该被认为「有筛选」。
      expect(const TransactionFilter().activeFilterCount, 0);
      // 「全部时间」是放宽时间范围，时间由区间标签展示，不计入附加条件徽标。
      expect(TransactionFilter.all.activeFilterCount, 0);
      expect(
        const TransactionFilter(
          kinds: <TxKind>{TxKind.expense},
          keyword: 'a',
        ).activeFilterCount,
        2,
      );
      expect(
        const TransactionFilter(
          accountIds: <String>{'acc'},
          categoryIds: <String>{'cat'},
        ).activeFilterCount,
        2,
      );
    });

    test('isUnfiltered 判定以「本月」为基准', () {
      // 账单页默认就是「本月」，因此默认视图是无筛选的。
      expect(const TransactionFilter().isUnfiltered, isTrue);
      // 「全部时间」是用户主动放宽了时间范围，属于「有筛选」。
      expect(TransactionFilter.all.isUnfiltered, isFalse);
      expect(
        const TransactionFilter(
          preset: DateRangePreset.all,
          keyword: 'x',
        ).isUnfiltered,
        isFalse,
      );
      expect(
        const TransactionFilter(
          kinds: <TxKind>{TxKind.expense},
        ).isUnfiltered,
        isFalse,
      );
      expect(
        const TransactionFilter(
          preset: DateRangePreset.lastMonth,
        ).isUnfiltered,
        isFalse,
      );
    });

    test('copyWith 与 cleared', () {
      const TransactionFilter base = TransactionFilter();
      final TransactionFilter next = base.copyWith(keyword: 'abc');
      expect(next.keyword, 'abc');
      expect(next.preset, base.preset);
      expect(next.cleared(), const TransactionFilter());
    });

    test('相等性比较包含集合内容', () {
      const TransactionFilter a = TransactionFilter(
        accountIds: <String>{'x', 'y'},
      );
      const TransactionFilter b = TransactionFilter(
        accountIds: <String>{'y', 'x'},
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('rangeLabel 展示', () {
      expect(const TransactionFilter().rangeLabel, '本月');
      expect(TransactionFilter.all.rangeLabel, '全部');
      expect(
        TransactionFilter(
          preset: DateRangePreset.custom,
          customStart: DateTime(2026, 3, 1),
          customEndExclusive: DateTime(2026, 3, 15),
        ).rangeLabel,
        '2026-03-01 ~ 2026-03-14',
      );
    });

    test('labelWith：自定义未选区间时回落到「自定义」而不是当前预设名', () {
      // 回归用例：早先它回落到 `label`，而「自定义」那颗 chip 传的是
      // `_draft.preset`（默认「本月」），于是 chip 显示成「本月」，
      // 与真正的「本月」chip 同名，用户无法区分。
      expect(DateRangePreset.custom.labelWith(), '自定义');
      expect(
        DateRangePreset.custom.labelWith(
          start: DateTime(2026, 3, 10),
          endExclusive: DateTime(2026, 3, 12),
        ),
        '2026-03-10 ~ 2026-03-11',
      );
      // 只填了一头时同样回落到 fallback，不会给出半截区间。
      expect(
        DateRangePreset.custom.labelWith(start: DateTime(2026, 3, 10)),
        '自定义',
      );
      // 非自定义预设不受 start/end 影响。
      expect(
        DateRangePreset.thisMonth.labelWith(start: DateTime(2026, 3, 10)),
        '本月',
      );
      expect(DateRangePreset.all.labelWith(), '全部');
    });
  });
}
