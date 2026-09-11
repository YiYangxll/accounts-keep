/// 纯函数选择器：所有账目统计都在这里完成，便于单元测试与复用。
///
/// 约定：传入的交易列表应已通过 [Selectors.active] 过滤掉软删除记录。
library;

import '../core/date_x.dart';
import 'account.dart';
import 'category.dart';
import 'enums.dart';
import 'transaction.dart';

/// 某个账户的余额。
final class AccountBalance {
  /// 构造。
  const AccountBalance({required this.account, required this.balanceCents});

  /// 账户。
  final Account account;

  /// 当前余额（分）。信用卡为负数表示欠款。
  final int balanceCents;

  /// 负债账户展示用的「待还款」金额（分，非负）。
  int get debtCents => balanceCents < 0 ? -balanceCents : 0;
}

/// 一段时间内的收支汇总。
final class PeriodSummary {
  /// 构造。
  const PeriodSummary({
    required this.incomeCents,
    required this.expenseCents,
    required this.transferCents,
    required this.transactionCount,
  });

  /// 空汇总。
  static const PeriodSummary empty = PeriodSummary(
    incomeCents: 0,
    expenseCents: 0,
    transferCents: 0,
    transactionCount: 0,
  );

  /// 收入合计（分）。
  final int incomeCents;

  /// 支出合计（分）。
  final int expenseCents;

  /// 转账合计（分），不计入收支。
  final int transferCents;

  /// 交易笔数（含转账）。
  final int transactionCount;

  /// 结余 = 收入 − 支出（分），可为负。
  int get netCents => incomeCents - expenseCents;

  /// 是否没有任何记录。
  bool get isEmpty =>
      incomeCents == 0 && expenseCents == 0 && transferCents == 0;
}

/// 分类聚合项。
final class CategoryTotal {
  /// 构造。
  const CategoryTotal({
    required this.categoryId,
    required this.amountCents,
    required this.transactionCount,
    this.category,
  });

  /// 分类 id。
  final String categoryId;

  /// 合计金额（分）。
  final int amountCents;

  /// 笔数。
  final int transactionCount;

  /// 分类实体；已删除或缺失时为 null。
  final Category? category;

  /// 展示名称（分类缺失时给出占位）。
  String get name => category?.name ?? '未分类';
}

/// 分类聚合项及其占比。
final class CategoryShare {
  /// 构造。
  const CategoryShare({required this.total, required this.share});

  /// 聚合项。
  final CategoryTotal total;

  /// 占比（0–1）。
  final double share;

  /// 百分比文本（保留一位小数）。
  String get percentText => '${(share * 100).toStringAsFixed(1)}%';
}

/// 单个账户的消费排行项。
final class AccountExpenseTotal {
  /// 构造。
  const AccountExpenseTotal({
    required this.accountId,
    required this.expenseCents,
  });

  /// 账户 id。
  final String accountId;

  /// 支出合计（分）。
  final int expenseCents;
}

/// 账目统计选择器。
abstract final class Selectors {
  /// 过滤掉软删除的交易。
  static List<Transaction> active(List<Transaction> transactions) =>
      transactions.where((Transaction t) => !t.isDeleted).toList();

  /// 按月键过滤（依据交易发生时的本地墙上时间）。
  static List<Transaction> inMonth(
          List<Transaction> transactions, MonthKey month) =>
      transactions.where((Transaction t) => t.monthKey == month).toList();

  /// 按左闭右开的本地时间区间过滤。
  static List<Transaction> inRange(
    List<Transaction> transactions,
    DateTime startInclusive,
    DateTime endExclusive,
  ) {
    return transactions.where((Transaction t) {
      final DateTime local = t.wallClock;
      return !local.isBefore(startInclusive) && local.isBefore(endExclusive);
    }).toList();
  }

  /// 按类型过滤。
  static List<Transaction> ofKind(
          List<Transaction> transactions, TxKind kind) =>
      transactions.where((Transaction t) => t.kind == kind).toList();

  /// 汇总给定交易的收入、支出与转账。
  static PeriodSummary summarize(List<Transaction> transactions) {
    int income = 0;
    int expense = 0;
    int transfer = 0;
    for (final Transaction t in transactions) {
      switch (t.kind) {
        case TxKind.income:
          income += t.amountCents;
        case TxKind.expense:
          expense += t.amountCents;
        case TxKind.transfer:
          transfer += t.amountCents;
      }
    }
    return PeriodSummary(
      incomeCents: income,
      expenseCents: expense,
      transferCents: transfer,
      transactionCount: transactions.length,
    );
  }

  /// 计算单个账户在给定交易集合下的余额。
  ///
  /// * 资产账户：期初 + 收入 − 支出 + 转入 − 转出（含手续费）。
  /// * 信用卡：期初（负数表示已欠款）+ 消费（支出）使余额更负。
  static int accountBalance(Account account, List<Transaction> transactions) {
    int balance = account.initialBalanceCents;
    for (final Transaction t in transactions) {
      if (t.isDeleted) {
        continue;
      }
      switch (t.kind) {
        case TxKind.income:
          if (t.accountId == account.id) {
            balance += t.amountCents;
          }
        case TxKind.expense:
          if (t.accountId == account.id) {
            balance -= t.amountCents;
          }
        case TxKind.transfer:
          if (t.accountId == account.id) {
            balance -= t.amountCents + t.feeCents;
          }
          if (t.toAccountId == account.id) {
            balance += t.amountCents;
          }
      }
    }
    return balance;
  }

  /// 计算所有未归档账户的余额。
  static List<AccountBalance> balances(
    List<Account> accounts,
    List<Transaction> transactions, {
    bool includeArchived = false,
  }) {
    final List<Account> source = includeArchived
        ? accounts
        : accounts.where((Account a) => !a.isArchived).toList();
    final List<Account> sorted = List<Account>.of(source)
      ..sort((Account a, Account b) {
        final int byOrder = a.sortOrder.compareTo(b.sortOrder);
        return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
      });
    return sorted
        .map((Account a) => AccountBalance(
              account: a,
              balanceCents: accountBalance(a, transactions),
            ))
        .toList();
  }

  /// 净资产 = 所有**未归档**账户余额之和（转账自动抵消）。
  ///
  /// 归档账户**整体不计入**：连它流水带来的影响也一并排除，
  /// 因为归档的语义是「不再参与统计、但历史仍可查」。
  /// 需要包含归档账户的总额（例如做对账校验）时传 `includeArchived: true`。
  static int netWorth(
    List<Account> accounts,
    List<Transaction> transactions, {
    bool includeArchived = false,
  }) {
    int total = 0;
    for (final AccountBalance b in balances(
      accounts,
      transactions,
      includeArchived: includeArchived,
    )) {
      total += b.balanceCents;
    }
    return total;
  }

  /// 总资产：仅统计余额为正的未归档账户。
  static int totalAssets(
      List<Account> accounts, List<Transaction> transactions) {
    int total = 0;
    for (final AccountBalance b in balances(accounts, transactions)) {
      if (b.balanceCents > 0) {
        total += b.balanceCents;
      }
    }
    return total;
  }

  /// 总负债：所有未归档账户的负余额绝对值之和。
  static int totalLiabilities(
    List<Account> accounts,
    List<Transaction> transactions,
  ) {
    int total = 0;
    for (final AccountBalance b in balances(accounts, transactions)) {
      if (b.balanceCents < 0) {
        total += -b.balanceCents;
      }
    }
    return total;
  }

  /// 按发生时间倒序排列（同时间按 id 稳定排序）。
  static List<Transaction> sortedByTimeDesc(List<Transaction> transactions) {
    final List<Transaction> sorted = List<Transaction>.of(transactions)
      ..sort((Transaction a, Transaction b) {
        final int byTime = b.wallClock.compareTo(a.wallClock);
        return byTime != 0 ? byTime : b.id.compareTo(a.id);
      });
    return sorted;
  }

  /// 按分类聚合指定类型的交易，金额降序；金额相同按分类名升序。
  static List<CategoryTotal> totalsByCategory(
    List<Transaction> transactions, {
    required TxKind kind,
    required List<Category> categories,
  }) {
    final Map<String, Category> byId = <String, Category>{
      for (final Category c in categories) c.id: c,
    };
    final Map<String, int> amount = <String, int>{};
    final Map<String, int> count = <String, int>{};
    for (final Transaction t in transactions) {
      if (t.kind != kind || t.isDeleted) {
        continue;
      }
      final String key = t.categoryId ?? '';
      amount[key] = (amount[key] ?? 0) + t.amountCents;
      count[key] = (count[key] ?? 0) + 1;
    }
    final List<CategoryTotal> result = amount.entries
        .map((MapEntry<String, int> e) => CategoryTotal(
              categoryId: e.key,
              amountCents: e.value,
              transactionCount: count[e.key] ?? 0,
              category: byId[e.key],
            ))
        .toList();
    result.sort((CategoryTotal a, CategoryTotal b) {
      final int byAmount = b.amountCents.compareTo(a.amountCents);
      return byAmount != 0 ? byAmount : a.name.compareTo(b.name);
    });
    return result;
  }

  /// 为分类聚合结果补充占比信息。
  static List<CategoryShare> withShares(List<CategoryTotal> totals) {
    int sum = 0;
    for (final CategoryTotal t in totals) {
      sum += t.amountCents;
    }
    if (sum == 0) {
      return const <CategoryShare>[];
    }
    return totals
        .map((CategoryTotal t) => CategoryShare(
              total: t,
              share: t.amountCents / sum,
            ))
        .toList();
  }

  /// 计算若干连续月份的收入/支出趋势，按时间升序。
  static List<PeriodSummary> monthlyTrend(
    List<Transaction> transactions,
    MonthKey endMonth,
    int monthCount,
  ) {
    if (monthCount <= 0) {
      return const <PeriodSummary>[];
    }
    final MonthKey start = endMonth.shift(-(monthCount - 1));
    final Map<MonthKey, List<Transaction>> grouped =
        <MonthKey, List<Transaction>>{};
    for (int i = 0; i < monthCount; i++) {
      grouped[start.shift(i)] = <Transaction>[];
    }
    for (final Transaction t in transactions) {
      if (t.isDeleted) {
        continue;
      }
      final List<Transaction>? bucket = grouped[t.monthKey];
      bucket?.add(t);
    }
    final List<PeriodSummary> result = <PeriodSummary>[];
    for (int i = 0; i < monthCount; i++) {
      result.add(summarize(grouped[start.shift(i)]!));
    }
    return result;
  }

  /// 按账户汇总支出，金额降序。
  static List<AccountExpenseTotal> expenseByAccount(
    List<Transaction> transactions,
  ) {
    final Map<String, int> amount = <String, int>{};
    for (final Transaction t in transactions) {
      if (t.isDeleted || t.kind != TxKind.expense) {
        continue;
      }
      amount[t.accountId] = (amount[t.accountId] ?? 0) + t.amountCents;
    }
    final List<AccountExpenseTotal> result = amount.entries
        .map((MapEntry<String, int> e) =>
            AccountExpenseTotal(accountId: e.key, expenseCents: e.value))
        .toList();
    result.sort((AccountExpenseTotal a, AccountExpenseTotal b) =>
        b.expenseCents.compareTo(a.expenseCents));
    return result;
  }

  /// 计算两个金额的环比变化率；基期为 0 时返回 null。
  static double? changeRate(int current, int previous) {
    if (previous == 0) {
      return null;
    }
    return (current - previous) / previous;
  }
}
