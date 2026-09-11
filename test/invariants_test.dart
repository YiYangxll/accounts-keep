/// 任意操作序列下的不变量测试（属性测试）。
///
/// 思路：不逐条枚举"应该怎样"，而是先定义「一个健康账本必须永远满足的规则」，
/// 然后用**固定种子的随机操作序列**（含收入、支出、转账、增删改、边界值、
/// 以及故意非法输入）反复执行，每一步之后都断言全部不变量。
/// 任何一次不成立就说明代码有问题。
///
/// 固定种子保证可复现：失败时日志会打印完整操作序列，可照着复现。
library;

import 'dart:math';

import 'package:accounts_keep/core/date_x.dart';
import 'package:accounts_keep/core/money.dart';
import 'package:accounts_keep/core/result.dart';
import 'package:accounts_keep/data/ledger_data.dart';
import 'package:accounts_keep/data/ledger_repository.dart';
import 'package:accounts_keep/domain/account.dart';
import 'package:accounts_keep/domain/category.dart';
import 'package:accounts_keep/domain/enums.dart';
import 'package:accounts_keep/domain/selectors.dart';
import 'package:accounts_keep/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

/// 操作日志：失败时打印出来即可复现。
final class OpLog {
  final List<String> _steps = <String>[];

  void add(String step) => _steps.add(step);

  String dump() => _steps.isEmpty
      ? '  (无)'
      : _steps
          .asMap()
          .entries
          .map((MapEntry<int, String> e) =>
              '  ${(e.key + 1).toString().padLeft(4)}. ${e.value}')
          .join('\n');
}

void main() {
  group('不变量：随机操作序列后账本必须自洽', () {
    for (final int seed in <int>[1, 7, 42, 2026, 999983]) {
      test('seed=$seed', () async {
        final OpLog log = OpLog();
        final TestLedger ledger = await TestLedger.create();
        addTearDown(ledger.dispose);

        final Fuzzer fuzzer = Fuzzer(random: Random(seed), log: log);
        await fuzzer.run(ledger.repository, steps: 220);

        log.add('reload()：从磁盘重新载入');
        expect(
          (await ledger.repository.load()).isOk,
          isTrue,
          reason: '重新载入应成功',
        );
        expectInvariants(ledger.repository, log);
      });
    }
  });

  group('不变量：固定序列（含收入）', () {
    test('收入 -> 支出 -> 转账 -> 编辑 -> 软删/撤销 -> 再收入', () async {
      final OpLog log = OpLog();
      final TestLedger ledger = await TestLedger.create();
      addTearDown(ledger.dispose);
      final LedgerRepository repo = ledger.repository;

      final String cash = ledger.cashId;
      final Account bank = repo.data.activeAccounts
          .firstWhere((Account a) => a.kind == AccountKind.debitCard);
      final List<Category> incomeCats = repo.data.categories
          .where((Category c) => c.kind == CategoryKind.income)
          .toList();
      final String food =
          repo.data.categories.firstWhere((Category c) => c.name == '餐饮').id;

      log.add('收入 10000.00 到现金，分类=${incomeCats.first.name}');
      expect(
        (await repo.addTransaction(
          income(
            id: 'i1',
            amountCents: 1000000,
            accountId: cash,
            categoryId: incomeCats.first.id,
            occurredAt: DateTime(2026, 3, 1, 9),
          ),
        ))
            .isOk,
        isTrue,
      );
      expectInvariants(repo, log);

      log.add('支出 12.34 从现金，分类=餐饮');
      expect(
        (await repo.addTransaction(
          expense(
            id: 'e1',
            amountCents: 1234,
            accountId: cash,
            categoryId: food,
            occurredAt: DateTime(2026, 3, 2, 12),
          ),
        ))
            .isOk,
        isTrue,
      );
      expectInvariants(repo, log);

      log.add('转账 5000.00 现金->储蓄卡，手续费 2.00');
      expect(
        (await repo.addTransaction(
          transfer(
            id: 't1',
            amountCents: 500000,
            fromAccountId: cash,
            toAccountId: bank.id,
            feeCents: 200,
            occurredAt: DateTime(2026, 3, 3, 10),
          ),
        ))
            .isOk,
        isTrue,
      );
      expectInvariants(repo, log);

      log.add('编辑支出金额 -> 100.00');
      expect(
        (await repo.updateTransaction(
          repo.data.transactionById('e1')!.copyWith(amountCents: 10000),
        ))
            .isOk,
        isTrue,
      );
      expectInvariants(repo, log);

      log.add('软删除支出 e1');
      expect((await repo.deleteTransaction('e1')).isOk, isTrue);
      expectInvariants(repo, log);

      log.add('撤销删除 e1');
      expect((await repo.restoreTransaction('e1')).isOk, isTrue);
      expectInvariants(repo, log);

      log.add('再收入 250.50 到储蓄卡，分类=${incomeCats.last.name}');
      expect(
        (await repo.addTransaction(
          income(
            id: 'i2',
            amountCents: 25050,
            accountId: bank.id,
            categoryId: incomeCats.last.id,
            occurredAt: DateTime(2026, 3, 4, 9),
          ),
        ))
            .isOk,
        isTrue,
      );
      expectInvariants(repo, log);

      // 人工核算余额：现金 = +10000.00 -100.00 -5000.00 -2.00 = 4898.00
      expect(
        Selectors.accountBalance(
          repo.data.accountById(cash)!,
          repo.data.transactions,
        ),
        1000000 - 10000 - 500000 - 200,
      );
      // 储蓄卡 = +5000.00 + 250.50 = 5250.50
      expect(
        Selectors.accountBalance(
          repo.data.accountById(bank.id)!,
          repo.data.transactions,
        ),
        500000 + 25050,
      );
    });
  });

  group('不变量：金额边界值', () {
    test('0.01 / 1亿 / 超限 / 0 / 负数 都不会让账目出错', () async {
      final OpLog log = OpLog();
      final TestLedger ledger = await TestLedger.create();
      addTearDown(ledger.dispose);
      final LedgerRepository repo = ledger.repository;

      final String cash = ledger.cashId;
      final String salary = repo.data.categories
          .firstWhere((Category c) => c.kind == CategoryKind.income)
          .id;
      final String food =
          repo.data.categories.firstWhere((Category c) => c.name == '餐饮').id;

      log.add('收入 0.01（最小金额）');
      expect(
        (await repo.addTransaction(
          income(
            id: 'i_min',
            amountCents: 1,
            accountId: cash,
            categoryId: salary,
          ),
        ))
            .isOk,
        isTrue,
      );
      expectInvariants(repo, log);

      log.add('收入 1 亿元（上限）');
      expect(
        (await repo.addTransaction(
          income(
            id: 'i_max',
            amountCents: Money.maxCents,
            accountId: cash,
            categoryId: salary,
          ),
        ))
            .isOk,
        isTrue,
      );
      expectInvariants(repo, log);

      log.add('收入 1 亿元 + 1 分（应被拒绝）');
      final Result<Transaction> over = await repo.addTransaction(
        income(
          id: 'i_over',
          amountCents: Money.maxCents + 1,
          accountId: cash,
          categoryId: salary,
        ),
      );
      expect(over.isErr, isTrue, reason: '超过上限必须被拒绝');
      expect(repo.data.transactionById('i_over'), isNull);
      expectInvariants(repo, log);

      for (final int bad in <int>[
        0,
        -1,
        -Money.maxCents,
        -Money.maxCents - 1
      ]) {
        log.add('收入金额 $bad（应被拒绝）');
        expect(
          (await repo.addTransaction(
            income(
              id: 'i_bad_${bad.abs()}',
              amountCents: bad,
              accountId: cash,
              categoryId: salary,
            ),
          ))
              .isErr,
          isTrue,
          reason: '金额 $bad 必须被拒绝',
        );
        expectInvariants(repo, log);
      }

      // 到此为止：收入 1 分 + 收入 1 亿，支出 0（超限被拒绝）=> 余额 = 1 亿 + 1 分
      expect(
        Selectors.accountBalance(
          repo.data.accountById(cash)!,
          repo.data.transactions,
        ),
        Money.maxCents + 1,
        reason: '超限的支出没有落库，余额应保持 1 亿 + 1 分',
      );

      log.add('大额支出 1 亿（恰好花掉上限部分）');
      expect(
        (await repo.addTransaction(
          expense(
            id: 'e_big',
            amountCents: Money.maxCents,
            accountId: cash,
            categoryId: food,
          ),
        ))
            .isOk,
        isTrue,
      );
      expectInvariants(repo, log);
      expect(
        Selectors.accountBalance(
          repo.data.accountById(cash)!,
          repo.data.transactions,
        ),
        1,
        reason: '花掉 1 亿后应只剩最初那 1 分',
      );

      // 允许透支：再支出 500 元会把余额打成负数，但账目仍必须自洽。
      log.add('继续支出 500.00（透支，余额转负）');
      expect(
        (await repo.addTransaction(
          expense(
            id: 'e_overdraft',
            amountCents: 50000,
            accountId: cash,
            categoryId: food,
          ),
        ))
            .isOk,
        isTrue,
      );
      expectInvariants(repo, log);
      expect(
        Selectors.accountBalance(
          repo.data.accountById(cash)!,
          repo.data.transactions,
        ),
        1 - 50000,
        reason: '允许透支，余额应为负',
      );
    });
  });

  group('不变量：转账不凭空产生或消灭资产', () {
    test('任意多笔转账后净资产只被手续费改变', () async {
      final OpLog log = OpLog();
      final TestLedger ledger = await TestLedger.create();
      addTearDown(ledger.dispose);
      final LedgerRepository repo = ledger.repository;
      final Random random = Random(20260311);

      final int before =
          Selectors.netWorth(repo.data.accounts, repo.data.transactions);
      int fees = 0;
      int done = 0;

      for (int i = 0; i < 60; i++) {
        final List<Account> accounts = repo.data.activeAccounts;
        if (accounts.length < 2) {
          break;
        }
        final Account from = accounts[random.nextInt(accounts.length)];
        final List<Account> others =
            accounts.where((Account a) => a.id != from.id).toList();
        if (others.isEmpty) {
          break;
        }
        final Account to = others[random.nextInt(others.length)];
        final int amount = 1 + random.nextInt(500000);
        final int fee = random.nextInt(3) == 0 ? random.nextInt(1000) : 0;
        log.add('转账 $amount 分 ${from.name}->${to.name} 手续费 $fee');
        final Result<Transaction> r = await repo.addTransaction(
          transfer(
            id: 't_$i',
            amountCents: amount,
            fromAccountId: from.id,
            toAccountId: to.id,
            feeCents: fee,
          ),
        );
        expect(r.isOk, isTrue, reason: '合法转账不应失败：${r.error}');
        fees += fee;
        done++;
        expectInvariants(repo, log);

        expect(
          Selectors.netWorth(repo.data.accounts, repo.data.transactions),
          before - fees,
          reason: '净资产应只被累计手续费改变（本金在账户间抵消）',
        );
      }

      expect(done, greaterThan(0), reason: '应至少成功执行一笔转账');
      expect(fees, greaterThan(0), reason: '随机序列里应出现过手续费');
    });
  });

  group('不变量：收入不会破坏账目', () {
    test('大量收入后收入合计等于各笔之和、净资产随收入增长', () async {
      final OpLog log = OpLog();
      final TestLedger ledger = await TestLedger.create();
      addTearDown(ledger.dispose);
      final LedgerRepository repo = ledger.repository;
      final Random random = Random(314159);

      final String cash = ledger.cashId;
      final List<Category> incomes = repo.data.categories
          .where((Category c) => c.kind == CategoryKind.income)
          .toList();
      final int netWorthBefore =
          Selectors.netWorth(repo.data.accounts, repo.data.transactions);

      int expectedIncome = 0;
      for (int i = 0; i < 80; i++) {
        final Category category = incomes[random.nextInt(incomes.length)];
        final int amount = 1 + random.nextInt(999999);
        log.add('收入 $amount 分 分类=${category.name}');
        final Result<Transaction> r = await repo.addTransaction(
          income(
            id: 'i_$i',
            amountCents: amount,
            accountId: cash,
            categoryId: category.id,
            occurredAt: DateTime(2026, 3, 1 + (i % 28), 9),
          ),
        );
        expect(r.isOk, isTrue, reason: '收入不应失败：${r.error}');
        expectedIncome += amount;
        expectInvariants(repo, log);
      }

      final PeriodSummary summary =
          Selectors.summarize(repo.data.activeTransactions);
      expect(summary.incomeCents, expectedIncome, reason: '收入合计应等于各笔之和');
      expect(summary.expenseCents, 0);
      expect(
        Selectors.netWorth(repo.data.accounts, repo.data.transactions),
        netWorthBefore + expectedIncome,
        reason: '没有支出与手续费时，净资产应增加全部收入',
      );
    });

    test('每个账户的余额等于该账户全部收入之和', () async {
      final TestLedger ledger = await TestLedger.create();
      addTearDown(ledger.dispose);
      final LedgerRepository repo = ledger.repository;
      final Random random = Random(271828);

      final Map<String, int> perAccount = <String, int>{};
      final List<Account> accounts = repo.data.activeAccounts;
      final List<Category> incomes = repo.data.categories
          .where((Category c) => c.kind == CategoryKind.income)
          .toList();

      for (int i = 0; i < 50; i++) {
        final Account account = accounts[random.nextInt(accounts.length)];
        final Category category = incomes[random.nextInt(incomes.length)];
        final int amount = 1 + random.nextInt(100000);
        expect(
          (await repo.addTransaction(
            income(
              id: 'i_$i',
              amountCents: amount,
              accountId: account.id,
              categoryId: category.id,
            ),
          ))
              .isOk,
          isTrue,
        );
        perAccount[account.id] = (perAccount[account.id] ?? 0) + amount;
      }

      for (final Account account in accounts) {
        expect(
          Selectors.accountBalance(account, repo.data.transactions),
          perAccount[account.id] ?? 0,
          reason: '账户 ${account.name} 的余额应等于其收入合计',
        );
      }
    });
  });

  group('不变量：存档再读回必须与内存一致', () {
    test('随机 40 笔收支，重新载入后逐字段一致', () async {
      final TestLedger ledger = await TestLedger.create();
      addTearDown(ledger.dispose);
      final LedgerRepository repo = ledger.repository;
      final Random random = Random(161803);

      final List<Account> accounts = repo.data.activeAccounts;
      final List<Category> categories = repo.data.activeCategories;
      for (int i = 0; i < 40; i++) {
        final Account account = accounts[random.nextInt(accounts.length)];
        final Category category = categories[random.nextInt(categories.length)];
        final int amount = 1 + random.nextInt(100000);
        final DateTime when =
            DateTime(2026, 1 + random.nextInt(12), 1 + random.nextInt(28), 12);
        final Result<Transaction> r = category.kind == CategoryKind.income
            ? await repo.addTransaction(
                income(
                  id: 'tx_$i',
                  amountCents: amount,
                  accountId: account.id,
                  categoryId: category.id,
                  occurredAt: when,
                ),
              )
            : await repo.addTransaction(
                expense(
                  id: 'tx_$i',
                  amountCents: amount,
                  accountId: account.id,
                  categoryId: category.id,
                  occurredAt: when,
                ),
              );
        expect(r.isOk, isTrue);
      }

      final LedgerData inMemory = repo.data;
      expect((await repo.load()).isOk, isTrue);

      expect(repo.data.transactions.length, inMemory.transactions.length);
      expect(repo.data.accounts.length, inMemory.accounts.length);
      expect(repo.data.categories.length, inMemory.categories.length);

      for (final Transaction before in inMemory.transactions) {
        final Transaction? after = repo.data.transactionById(before.id);
        expect(after, isNotNull, reason: '流水 ${before.id} 重载后应仍存在');
        expect(after!.amountCents, before.amountCents);
        expect(after.kind, before.kind);
        expect(after.accountId, before.accountId);
        expect(after.toAccountId, before.toAccountId);
        expect(after.feeCents, before.feeCents);
        expect(after.categoryId, before.categoryId);
        expect(after.utcOffsetMinutes, before.utcOffsetMinutes);
        expect(after.occurredAtUtc, before.occurredAtUtc);
        // 墙上时间（用户看到的日期）必须完全不变。
        expect(after.wallClock.year, before.wallClock.year);
        expect(after.wallClock.month, before.wallClock.month);
        expect(after.wallClock.day, before.wallClock.day);
        expect(after.wallClock.hour, before.wallClock.hour);
        expect(after.wallClock.minute, before.wallClock.minute);
      }

      for (final Account account in inMemory.accounts) {
        expect(
          Selectors.accountBalance(account, repo.data.transactions),
          Selectors.accountBalance(account, inMemory.transactions),
          reason: '账户 ${account.name} 重载后余额应不变',
        );
      }
    });
  });
}

/// 通用不变量断言：任何操作之后都必须成立。
void expectInvariants(LedgerRepository repo, OpLog log) {
  final LedgerData data = repo.data;
  final String ctx = '\n操作序列：\n${log.dump()}';

  // 1. 引用完整性 + 领域不变量。
  for (final Transaction t in data.transactions) {
    expect(
      data.accountById(t.accountId),
      isNotNull,
      reason: '流水 ${t.id} 引用了不存在的账户 ${t.accountId}$ctx',
    );
    if (t.toAccountId != null) {
      expect(
        data.accountById(t.toAccountId!),
        isNotNull,
        reason: '流水 ${t.id} 引用了不存在的转入账户 ${t.toAccountId}$ctx',
      );
      expect(
        t.toAccountId,
        isNot(t.accountId),
        reason: '流水 ${t.id} 的转出与转入账户相同$ctx',
      );
    }
    if (t.categoryId != null) {
      final Category? category = data.categoryById(t.categoryId!);
      expect(category, isNotNull, reason: '流水 ${t.id} 引用了不存在的分类$ctx');
      expect(
        category!.kind.asTxKind,
        t.kind,
        reason: '流水 ${t.id} 的分类类型与交易类型不一致$ctx',
      );
    }
    expect(t.validate(), isNull, reason: '流水 ${t.id} 不合法$ctx');
    expect(
      Money.isValidAmount(t.amountCents),
      isTrue,
      reason: '流水 ${t.id} 的金额不在合法范围$ctx',
    );
    expect(
      t.feeCents,
      greaterThanOrEqualTo(0),
      reason: '流水 ${t.id} 的手续费为负$ctx',
    );
  }

  // 2. 主键唯一。
  final Set<String> txIds = <String>{};
  for (final Transaction t in data.transactions) {
    expect(txIds.add(t.id), isTrue, reason: '流水 id 重复：${t.id}$ctx');
  }
  final Set<String> accountIds = <String>{};
  final Set<String> accountNames = <String>{};
  for (final Account a in data.accounts) {
    expect(accountIds.add(a.id), isTrue, reason: '账户 id 重复：${a.id}$ctx');
    expect(a.name.trim(), isNotEmpty, reason: '账户名为空$ctx');
    expect(accountNames.add(a.name), isTrue, reason: '账户名重复：${a.name}$ctx');
  }
  final Set<String> categoryIds = <String>{};
  for (final Category c in data.categories) {
    expect(categoryIds.add(c.id), isTrue, reason: '分类 id 重复：${c.id}$ctx');
    expect(c.name.trim(), isNotEmpty, reason: '分类名为空$ctx');
  }

  // 3. 净资产 == 各账户余额之和。
  final int netWorth = Selectors.netWorth(data.accounts, data.transactions);
  int balanceSum = 0;
  for (final AccountBalance b in Selectors.balances(
    data.accounts,
    data.transactions,
  )) {
    balanceSum += b.balanceCents;
  }
  expect(netWorth, balanceSum, reason: '净资产应等于未归档账户余额之和$ctx');

  // 4. 金额守恒：净资产 == （全部期初 + 全部收入 - 全部支出 - 全部手续费） - 归档账户余额合计。
  //
  // 口径说明：归档账户**整体不计入净资产**（含它全部流水的影响）。
  // 归档的语义是「不再参与统计、但历史仍可查」。
  // 这里刻意用「先算全量、再减去归档部分」的方式，这样一旦归档账户的流水
  // 被错误计入或漏计，差额就会暴露出来，而不是被两边同时漏掉而掩盖。
  int fullTotal = 0;
  for (final Account a in data.accounts) {
    fullTotal += a.initialBalanceCents;
  }
  for (final Transaction t in Selectors.active(data.transactions)) {
    switch (t.kind) {
      case TxKind.income:
        fullTotal += t.amountCents;
      case TxKind.expense:
        fullTotal -= t.amountCents;
      case TxKind.transfer:
        fullTotal -= t.feeCents;
    }
  }

  int archivedSum = 0;
  int archivedInitial = 0;
  for (final AccountBalance b in Selectors.balances(
    data.accounts,
    data.transactions,
    includeArchived: true,
  )) {
    if (b.account.isArchived) {
      archivedSum += b.balanceCents;
      archivedInitial += b.account.initialBalanceCents;
    }
  }

  expect(
    netWorth,
    fullTotal - archivedSum,
    reason: '净资产应等于「全部期初 + 全部收支 - 手续费」减去归档账户余额合计；'
        '差额说明归档账户的流水影响被错误计入或漏计'
        '（归档余额合计=$archivedSum，归档期初合计=$archivedInitial）$ctx',
  );

  // 5. 汇总口径自洽。
  final PeriodSummary summary =
      Selectors.summarize(Selectors.active(data.transactions));
  expect(
    summary.netCents,
    summary.incomeCents - summary.expenseCents,
    reason: '结余应等于收入减支出$ctx',
  );

  // 6. 按分类聚合不会丢钱。
  final List<CategoryTotal> totals = Selectors.totalsByCategory(
    Selectors.active(data.transactions),
    kind: TxKind.expense,
    categories: data.categories,
  );
  final int categorySum =
      totals.fold(0, (int acc, CategoryTotal t) => acc + t.amountCents);
  int rawExpense = 0;
  for (final Transaction t in Selectors.active(data.transactions)) {
    if (t.kind == TxKind.expense) {
      rawExpense += t.amountCents;
    }
  }
  expect(
    categorySum,
    rawExpense,
    reason: '按分类聚合的支出合计应等于支出总额（分类归档也不能丢钱）$ctx',
  );

  // 7. 月份归属永远可算且合理。
  for (final Transaction t in data.transactions) {
    final MonthKey month = t.monthKey;
    expect(month.month, inInclusiveRange(1, 12));
    expect(month.year, inInclusiveRange(2000, 2100));
  }

  // 8. 时间倒序排序不抛异常且长度不变。
  expect(
    Selectors.sortedByTimeDesc(data.transactions).length,
    data.transactions.length,
  );
}

/// 随机操作生成器：覆盖增删改、收入/支出/转账、边界值与故意非法输入。
final class Fuzzer {
  Fuzzer({required this.random, required this.log});

  final Random random;
  final OpLog log;
  int _seq = 0;

  String _uid(String prefix) => '${prefix}_${_seq++}';

  Future<void> run(LedgerRepository repo, {required int steps}) async {
    for (int i = 0; i < steps; i++) {
      await _oneStep(repo);
    }
  }

  Future<void> _oneStep(LedgerRepository repo) async {
    final int dice = random.nextInt(100);
    if (dice < 22) {
      await _addIncome(repo);
    } else if (dice < 46) {
      await _addExpense(repo);
    } else if (dice < 58) {
      await _addTransfer(repo);
    } else if (dice < 66) {
      await _editTransaction(repo);
    } else if (dice < 74) {
      await _deleteOrRestore(repo);
    } else if (dice < 82) {
      await _tryIllegalTransaction(repo);
    } else if (dice < 88) {
      await _addCategory(repo);
    } else if (dice < 92) {
      await _editOrDeleteCategory(repo);
    } else if (dice < 96) {
      await _addAccount(repo);
    } else {
      await _archiveOrRemoveAccount(repo);
    }
  }

  Future<void> _addIncome(LedgerRepository repo) async {
    final List<Account> accounts = repo.data.activeAccounts;
    final List<Category> incomes = repo.data.activeCategories
        .where((Category c) => c.kind == CategoryKind.income)
        .toList();
    if (accounts.isEmpty || incomes.isEmpty) {
      return;
    }
    final Account account = accounts[random.nextInt(accounts.length)];
    final Category category = incomes[random.nextInt(incomes.length)];
    final int amount = _randomAmount();
    final String id = _uid('i');
    log.add('收入 id=$id 金额=$amount 账户=${account.name} 分类=${category.name}');
    final Result<Transaction> r = await repo.addTransaction(
      income(
        id: id,
        amountCents: amount,
        accountId: account.id,
        categoryId: category.id,
        occurredAt: _randomWhen(),
      ),
    );
    expect(r.isOk, isTrue, reason: '合法的收入操作不应失败：${r.error}');
    expectInvariants(repo, log);
  }

  Future<void> _addExpense(LedgerRepository repo) async {
    final List<Account> accounts = repo.data.activeAccounts;
    final List<Category> expenses = repo.data.activeCategories
        .where((Category c) => c.kind == CategoryKind.expense)
        .toList();
    if (accounts.isEmpty || expenses.isEmpty) {
      return;
    }
    final Account account = accounts[random.nextInt(accounts.length)];
    final Category category = expenses[random.nextInt(expenses.length)];
    final int amount = _randomAmount();
    final String id = _uid('e');
    log.add('支出 id=$id 金额=$amount 账户=${account.name} 分类=${category.name}');
    final Result<Transaction> r = await repo.addTransaction(
      expense(
        id: id,
        amountCents: amount,
        accountId: account.id,
        categoryId: category.id,
        occurredAt: _randomWhen(),
      ),
    );
    expect(r.isOk, isTrue, reason: '合法的支出操作不应失败：${r.error}');
    expectInvariants(repo, log);
  }

  Future<void> _addTransfer(LedgerRepository repo) async {
    final List<Account> accounts = repo.data.activeAccounts;
    if (accounts.length < 2) {
      return;
    }
    final Account from = accounts[random.nextInt(accounts.length)];
    final List<Account> others =
        accounts.where((Account a) => a.id != from.id).toList();
    if (others.isEmpty) {
      return;
    }
    final Account to = others[random.nextInt(others.length)];
    final int amount = _randomAmount();
    final int fee = random.nextInt(4) == 0 ? random.nextInt(2000) : 0;
    final String id = _uid('t');
    log.add('转账 id=$id 金额=$amount ${from.name}->${to.name} 手续费=$fee');
    final Result<Transaction> r = await repo.addTransaction(
      transfer(
        id: id,
        amountCents: amount,
        fromAccountId: from.id,
        toAccountId: to.id,
        feeCents: fee,
        occurredAt: _randomWhen(),
      ),
    );
    expect(r.isOk, isTrue, reason: '合法的转账不应失败：${r.error}');
    expectInvariants(repo, log);
  }

  Future<void> _editTransaction(LedgerRepository repo) async {
    final List<Transaction> all = repo.data.transactions;
    if (all.isEmpty) {
      return;
    }
    final Transaction t = all[random.nextInt(all.length)];
    if (t.kind == TxKind.transfer) {
      final int newFee = random.nextInt(500);
      log.add('编辑 ${t.id} 手续费 -> $newFee');
      final Result<Transaction> r =
          await repo.updateTransaction(t.copyWith(feeCents: newFee));
      expect(r.isOk, isTrue, reason: '编辑手续费不应失败：${r.error}');
    } else {
      final int newAmount = _randomAmount();
      log.add('编辑 ${t.id} 金额 -> $newAmount');
      final Result<Transaction> r =
          await repo.updateTransaction(t.copyWith(amountCents: newAmount));
      expect(r.isOk, isTrue, reason: '编辑金额不应失败：${r.error}');
    }
    expectInvariants(repo, log);
  }

  Future<void> _deleteOrRestore(LedgerRepository repo) async {
    final List<Transaction> all = repo.data.transactions;
    if (all.isEmpty) {
      return;
    }
    final Transaction t = all[random.nextInt(all.length)];
    if (t.isDeleted) {
      log.add('恢复 ${t.id}');
      expect((await repo.restoreTransaction(t.id)).isOk, isTrue);
    } else {
      log.add('软删除 ${t.id}');
      expect((await repo.deleteTransaction(t.id)).isOk, isTrue);
    }
    expectInvariants(repo, log);
  }

  /// 故意提交非法操作：必须被拒绝，且账本不受影响。
  Future<void> _tryIllegalTransaction(LedgerRepository repo) async {
    final List<Account> accounts = repo.data.activeAccounts;
    final List<Category> incomes = repo.data.activeCategories
        .where((Category c) => c.kind == CategoryKind.income)
        .toList();
    final List<Category> expenses = repo.data.activeCategories
        .where((Category c) => c.kind == CategoryKind.expense)
        .toList();
    if (accounts.isEmpty || incomes.isEmpty || expenses.isEmpty) {
      return;
    }
    final Account account = accounts[random.nextInt(accounts.length)];
    final int before = repo.data.transactions.length;
    final String id = _uid('bad');

    Result<Transaction> r;
    String what;
    switch (random.nextInt(6)) {
      case 0:
        what = '金额 0';
        r = await repo.addTransaction(
          income(
            id: id,
            amountCents: 0,
            accountId: account.id,
            categoryId: incomes.first.id,
          ),
        );
      case 1:
        what = '金额为负';
        r = await repo.addTransaction(
          expense(
            id: id,
            amountCents: -random.nextInt(1000) - 1,
            accountId: account.id,
            categoryId: expenses.first.id,
          ),
        );
      case 2:
        what = '超过上限';
        r = await repo.addTransaction(
          income(
            id: id,
            amountCents: Money.maxCents + 1 + random.nextInt(1000),
            accountId: account.id,
            categoryId: incomes.first.id,
          ),
        );
      case 3:
        what = '引用不存在的账户';
        r = await repo.addTransaction(
          expense(
            id: id,
            amountCents: 100,
            accountId: 'acc_does_not_exist',
            categoryId: expenses.first.id,
          ),
        );
      case 4:
        what = '引用不存在的分类';
        r = await repo.addTransaction(
          expense(
            id: id,
            amountCents: 100,
            accountId: account.id,
            categoryId: 'cat_does_not_exist',
          ),
        );
      default:
        what = '用收入分类记支出（类型不匹配）';
        r = await repo.addTransaction(
          expense(
            id: id,
            amountCents: 100,
            accountId: account.id,
            categoryId: incomes.first.id,
          ),
        );
    }

    log.add('非法操作：$what');
    expect(r.isErr, isTrue, reason: '非法操作必须被拒绝：$what');
    expect(
      repo.data.transactionById(id),
      isNull,
      reason: '被拒绝的流水绝不能落库：$what',
    );
    expect(
      repo.data.transactions.length,
      before,
      reason: '被拒绝的操作不应改变流水数量：$what',
    );
    expectInvariants(repo, log);
  }

  Future<void> _addCategory(LedgerRepository repo) async {
    _seq++;
    final CategoryKind kind =
        random.nextBool() ? CategoryKind.expense : CategoryKind.income;
    final String id = _uid('selfcat');
    final String name = '自定义${kind == CategoryKind.expense ? '支出' : '收入'}$_seq';
    log.add('新增分类 id=$id 名称=$name 类型=${kind.name}');
    final Result<Category> r = await repo.addCategory(
      Category(id: id, name: name, kind: kind),
    );
    expect(r.isOk, isTrue, reason: '新增分类不应失败：${r.error}');
    expectInvariants(repo, log);
  }

  Future<void> _editOrDeleteCategory(LedgerRepository repo) async {
    // 只动自定义分类，避免把内置分类删光导致后续没分类可用。
    final List<Category> custom = repo.data.categories
        .where((Category c) => c.id.startsWith('selfcat_'))
        .toList();
    if (custom.isEmpty) {
      return;
    }
    final Category c = custom[random.nextInt(custom.length)];
    if (random.nextBool()) {
      _seq++;
      final String newName = '改自${c.name}$_seq';
      log.add('改分类名 ${c.id} -> $newName');
      final Result<Category> r =
          await repo.updateCategory(c.copyWith(name: newName));
      expect(r.isOk, isTrue, reason: '改分类名不应失败：${r.error}');
    } else {
      log.add('删除分类 ${c.id}（有流水则归档）');
      final Result<bool> r = await repo.deleteCategory(c.id);
      expect(r.isOk, isTrue, reason: '删除分类不应失败：${r.error}');
    }
    expectInvariants(repo, log);
  }

  Future<void> _addAccount(LedgerRepository repo) async {
    _seq++;
    final String id = _uid('selfacc');
    final String name = '自定账户$_seq';
    final AccountKind kind =
        AccountKind.values[random.nextInt(AccountKind.values.length)];
    final int initial = random.nextInt(3) == 0
        ? -random.nextInt(100000)
        : random.nextInt(1000000);
    log.add('新增账户 id=$id 名称=$name 类型=${kind.name} 期初=$initial');
    final Result<Account> r = await repo.addAccount(
      Account(id: id, name: name, kind: kind, initialBalanceCents: initial),
    );
    expect(r.isOk, isTrue, reason: '新增账户不应失败：${r.error}');
    expectInvariants(repo, log);
  }

  Future<void> _archiveOrRemoveAccount(LedgerRepository repo) async {
    // 账户数够多时才动，保证永远有可用的收支账户。
    final List<Account> accounts = repo.data.activeAccounts;
    if (accounts.length <= 3) {
      return;
    }
    final Account target = accounts[random.nextInt(accounts.length)];
    if (random.nextBool()) {
      log.add('归档账户 ${target.name}');
      final Result<Unit> r = await repo.deleteAccount(target.id);
      expect(r.isOk, isTrue, reason: '归档账户不应失败：${r.error}');
    } else {
      log.add('尝试物理删除账户 ${target.name}');
      final Result<Unit> r = await repo.removeAccount(target.id);
      if (r.isErr) {
        expect(
          repo.data.accountById(target.id),
          isNotNull,
          reason: '删除被拒绝时账户必须还在',
        );
      }
    }
    expectInvariants(repo, log);
  }

  int _randomAmount() {
    final int dice = random.nextInt(100);
    if (dice < 5) {
      return 1; // 最小金额
    }
    if (dice < 10) {
      return Money.maxCents; // 上限金额
    }
    if (dice < 20) {
      return 100 + random.nextInt(1000); // 小额
    }
    return 1 + random.nextInt(5000000);
  }

  DateTime _randomWhen() {
    final int year = 2024 + random.nextInt(4);
    final int month = 1 + random.nextInt(12);
    final int day = 1 + random.nextInt(28);
    final int hour = random.nextInt(24);
    return DateTime(year, month, day, hour, random.nextInt(60));
  }
}
