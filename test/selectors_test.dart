/// 选择器测试：余额、净资产、分类聚合与趋势。
library;

import 'package:accounts_keep/core/date_x.dart';
import 'package:accounts_keep/domain/account.dart';
import 'package:accounts_keep/domain/category.dart';
import 'package:accounts_keep/domain/enums.dart';
import 'package:accounts_keep/domain/selectors.dart';
import 'package:accounts_keep/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

void main() {
  group('账户余额', () {
    final Account cash = account(id: 'cash', name: '现金');
    final Account bank = account(id: 'bank', name: '储蓄卡');
    final Account credit = account(
      id: 'credit',
      name: '信用卡',
      kind: AccountKind.creditCard,
      initialBalanceCents: -20000,
    );

    test('收入增加、支出减少', () {
      final List<Transaction> txs = <Transaction>[
        income(
          id: 'i1',
          amountCents: 100000,
          accountId: 'cash',
          categoryId: 'salary',
        ),
        expense(
          id: 'e1',
          amountCents: 3000,
          accountId: 'cash',
          categoryId: 'food',
        ),
      ];
      expect(Selectors.accountBalance(cash, txs), 97000);
    });

    test('转账从转出账户扣减并计入转入账户', () {
      final List<Transaction> txs = <Transaction>[
        transfer(
          id: 't1',
          amountCents: 5000,
          fromAccountId: 'cash',
          toAccountId: 'bank',
        ),
      ];
      expect(Selectors.accountBalance(cash, txs), -5000);
      expect(Selectors.accountBalance(bank, txs), 5000);
    });

    test('手续费从转出账户扣除，不改变转入金额', () {
      final List<Transaction> txs = <Transaction>[
        transfer(
          id: 't1',
          amountCents: 5000,
          fromAccountId: 'cash',
          toAccountId: 'bank',
          feeCents: 200,
        ),
      ];
      expect(Selectors.accountBalance(cash, txs), -5200);
      expect(Selectors.accountBalance(bank, txs), 5000);
    });

    test('信用卡消费使欠款增加（余额更负）', () {
      final List<Transaction> txs = <Transaction>[
        expense(
          id: 'e1',
          amountCents: 15000,
          accountId: 'credit',
          categoryId: 'food',
        ),
      ];
      expect(Selectors.accountBalance(credit, txs), -35000);
    });

    test('软删除的记录不参与余额', () {
      final List<Transaction> txs = <Transaction>[
        expense(
          id: 'e1',
          amountCents: 15000,
          accountId: 'cash',
          categoryId: 'food',
        ).copyWith(deletedAtUtc: DateTime.utc(2026, 3, 16)),
      ];
      expect(Selectors.accountBalance(cash, txs), 0);
    });
  });

  group('净资产与转账不变性', () {
    test('只有手续费影响净资产，转账本金完全抵消', () {
      final List<Account> accounts = <Account>[
        account(id: 'a', name: 'A', initialBalanceCents: 100000),
        account(id: 'b', name: 'B', initialBalanceCents: 20000),
      ];
      final int before = Selectors.netWorth(accounts, const <Transaction>[]);
      final List<Transaction> after = <Transaction>[
        transfer(
          id: 't1',
          amountCents: 30000,
          fromAccountId: 'a',
          toAccountId: 'b',
          feeCents: 500,
        ),
      ];
      expect(
        Selectors.netWorth(accounts, after),
        before - 500,
        reason: '转账本金抵消，只有手续费影响净资产',
      );
      expect(Selectors.accountBalance(accounts[0], after), 69500);
      expect(Selectors.accountBalance(accounts[1], after), 50000);
    });

    test('无手续费转账净资产完全不变', () {
      final List<Account> accounts = <Account>[
        account(id: 'a', name: 'A', initialBalanceCents: 100000),
        account(id: 'b', name: 'B'),
      ];
      final List<Transaction> txs = <Transaction>[
        transfer(
          id: 't1',
          amountCents: 100000,
          fromAccountId: 'a',
          toAccountId: 'b',
        ),
      ];
      expect(Selectors.netWorth(accounts, txs), 100000);
      expect(Selectors.netWorth(accounts, const <Transaction>[]), 100000);
    });

    test('归档账户不计入净资产，但包含在 includeArchived 查询中', () {
      final List<Account> accounts = <Account>[
        account(id: 'a', name: 'A', initialBalanceCents: 1000),
        account(id: 'b', name: 'B', initialBalanceCents: 2000)
            .copyWith(archivedAt: DateTime.utc(2026, 3, 1)),
      ];
      expect(Selectors.netWorth(accounts, const <Transaction>[]), 1000);
      expect(
        Selectors.balances(
          accounts,
          const <Transaction>[],
          includeArchived: true,
        ).length,
        2,
      );
      expect(Selectors.balances(accounts, const <Transaction>[]).length, 1);
    });

    test('资产与负债分别汇总', () {
      final List<Account> accounts = <Account>[
        account(id: 'a', name: 'A', initialBalanceCents: 100000),
        account(
          id: 'c',
          name: '信用卡',
          kind: AccountKind.creditCard,
          initialBalanceCents: -30000,
        ),
      ];
      expect(Selectors.totalAssets(accounts, const <Transaction>[]), 100000);
      expect(
          Selectors.totalLiabilities(accounts, const <Transaction>[]), 30000);
    });

    test('信用卡欠款以「待还款」正数呈现', () {
      final List<Account> accounts = <Account>[
        account(
          id: 'c',
          name: '信用卡',
          kind: AccountKind.creditCard,
          initialBalanceCents: -12345,
        ),
      ];
      final AccountBalance balance =
          Selectors.balances(accounts, const <Transaction>[]).single;
      expect(balance.balanceCents, -12345);
      expect(balance.debtCents, 12345);
    });
  });

  group('汇总与聚合', () {
    late List<Transaction> txs;
    late List<Category> categories;

    setUp(() {
      categories = <Category>[
        category(id: 'food', name: '餐饮'),
        category(id: 'shopping', name: '购物'),
        category(id: 'salary', name: '工资', kind: CategoryKind.income),
      ];
      txs = <Transaction>[
        income(
          id: 'i1',
          amountCents: 1000000,
          accountId: 'cash',
          categoryId: 'salary',
          occurredAt: DateTime(2026, 3, 1, 9),
        ),
        expense(
          id: 'e1',
          amountCents: 3000,
          accountId: 'cash',
          categoryId: 'food',
          occurredAt: DateTime(2026, 3, 2, 12),
        ),
        expense(
          id: 'e2',
          amountCents: 5000,
          accountId: 'bank',
          categoryId: 'food',
          occurredAt: DateTime(2026, 3, 3, 19),
        ),
        expense(
          id: 'e3',
          amountCents: 20000,
          accountId: 'cash',
          categoryId: 'shopping',
          occurredAt: DateTime(2026, 3, 4, 15),
        ),
        expense(
          id: 'e4',
          amountCents: 1000,
          accountId: 'cash',
          categoryId: 'food',
          occurredAt: DateTime(2026, 2, 20, 12),
        ),
        transfer(
          id: 't1',
          amountCents: 50000,
          fromAccountId: 'cash',
          toAccountId: 'bank',
          occurredAt: DateTime(2026, 3, 5, 10),
        ),
      ];
    });

    test('汇总区分收入、支出与转账', () {
      final PeriodSummary summary = Selectors.summarize(txs);
      expect(summary.incomeCents, 1000000);
      expect(summary.expenseCents, 29000);
      expect(summary.transferCents, 50000);
      expect(summary.netCents, 971000);
      expect(summary.transactionCount, 6);
    });

    test('按月过滤使用本地月份归属', () {
      final List<Transaction> march =
          Selectors.inMonth(txs, const MonthKey(2026, 3));
      expect(march.length, 5);
      expect(Selectors.summarize(march).expenseCents, 28000);
    });

    test('分类聚合按金额降序，且只统计指定类型', () {
      final List<CategoryTotal> totals = Selectors.totalsByCategory(
        txs,
        kind: TxKind.expense,
        categories: categories,
      );
      expect(totals.length, 2);
      expect(totals.first.categoryId, 'shopping');
      expect(totals.first.amountCents, 20000);
      expect(totals.first.name, '购物');
      expect(totals.last.amountCents, 9000);
      expect(totals.last.transactionCount, 3);
    });

    test('占比之和为 1', () {
      final List<CategoryShare> shares = Selectors.withShares(
        Selectors.totalsByCategory(
          txs,
          kind: TxKind.expense,
          categories: categories,
        ),
      );
      final double sum = shares.fold(
        0,
        (double acc, CategoryShare s) => acc + s.share,
      );
      expect(sum, closeTo(1, 1e-9));
      expect(shares.first.percentText, endsWith('%'));
    });

    test('空数据返回空结果而不是抛错', () {
      expect(Selectors.withShares(const <CategoryTotal>[]), isEmpty);
      expect(Selectors.summarize(const <Transaction>[]).isEmpty, isTrue);
    });

    test('缺失分类时给出占位名称', () {
      final List<CategoryTotal> totals = Selectors.totalsByCategory(
        txs,
        kind: TxKind.expense,
        categories: const <Category>[],
      );
      expect(totals.first.name, '未分类');
    });

    test('12 个月趋势长度与顺序正确', () {
      final List<PeriodSummary> trend =
          Selectors.monthlyTrend(txs, const MonthKey(2026, 3), 12);
      expect(trend.length, 12);
      expect(trend.last.expenseCents, 28000);
      expect(trend[10].expenseCents, 1000);
      expect(trend.first.isEmpty, isTrue);
    });

    test('趋势月份数为 0 时返回空', () {
      expect(Selectors.monthlyTrend(txs, const MonthKey(2026, 3), 0), isEmpty);
    });

    test('按账户汇总支出', () {
      final List<AccountExpenseTotal> byAccount =
          Selectors.expenseByAccount(txs);
      expect(byAccount.first.accountId, 'cash');
      expect(byAccount.first.expenseCents, 24000);
      expect(byAccount.last.accountId, 'bank');
      expect(byAccount.last.expenseCents, 5000);
    });

    test('时间倒序排列', () {
      final List<Transaction> sorted = Selectors.sortedByTimeDesc(txs);
      for (int i = 0; i < sorted.length - 1; i++) {
        expect(sorted[i].wallClock.isBefore(sorted[i + 1].wallClock), isFalse);
      }
    });

    test('环比变化率在基期为 0 时返回 null', () {
      expect(Selectors.changeRate(100, 50), closeTo(1.0, 1e-9));
      expect(Selectors.changeRate(50, 100), closeTo(-0.5, 1e-9));
      expect(Selectors.changeRate(100, 0), isNull);
    });
  });
}
