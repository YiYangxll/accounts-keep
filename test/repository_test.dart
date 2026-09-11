/// 仓库测试：CRUD、软删除与撤销、账户删除策略、偏好持久化。
library;

import 'package:accounts_keep/core/result.dart';
import 'package:accounts_keep/data/ledger_repository.dart';
import 'package:accounts_keep/domain/account.dart';
import 'package:accounts_keep/domain/category.dart';
import 'package:accounts_keep/domain/enums.dart';
import 'package:accounts_keep/domain/ledger_error.dart';
import 'package:accounts_keep/domain/selectors.dart';
import 'package:accounts_keep/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

void main() {
  late TestLedger ledger;

  setUp(() async {
    ledger = await TestLedger.create();
  });

  tearDown(() async {
    await ledger.dispose();
  });

  String foodCategoryId() => ledger.repository.data.categories
      .firstWhere((Category c) => c.name == '餐饮')
      .id;

  group('初始化', () {
    test('首次加载写入默认账户与分类，且不注入假流水', () {
      final LedgerRepository repo = ledger.repository;
      expect(repo.isReady, isTrue);
      expect(repo.data.accounts.length, 5);
      expect(repo.data.categories.length, 16);
      expect(repo.data.transactions, isEmpty);
      expect(repo.isEmpty, isTrue);
    });

    test('重新加载后默认数据不会重复写入', () async {
      await ledger.repository.load();
      expect(ledger.repository.data.accounts.length, 5);
    });
  });

  group('交易 CRUD', () {
    test('新增流水后余额与列表同步更新', () async {
      final Result<Transaction> added = await ledger.repository.addTransaction(
        expense(
          id: 'tx_1',
          amountCents: 2500,
          accountId: ledger.cashId,
          categoryId: foodCategoryId(),
        ),
      );
      expect(added.isOk, isTrue);
      expect(added.value.createdAtUtc, isNotNull);
      expect(ledger.repository.data.transactions.length, 1);

      final Account cash = ledger.repository.data.accountById(ledger.cashId)!;
      expect(
        Selectors.accountBalance(cash, ledger.repository.data.transactions),
        -2500,
      );
    });

    test('新增后从磁盘重新载入仍能读到（真实落盘）', () async {
      await ledger.repository.addTransaction(
        expense(
          id: 'tx_1',
          amountCents: 2500,
          accountId: ledger.cashId,
          categoryId: foodCategoryId(),
        ),
      );
      await ledger.repository.load();
      expect(ledger.repository.data.transactions.length, 1);
      expect(ledger.repository.data.transactions.single.amountCents, 2500);
    });

    test('引用不存在的账户被拒绝', () async {
      final Result<Transaction> result = await ledger.repository.addTransaction(
        expense(
          id: 'tx_1',
          amountCents: 100,
          accountId: 'nope',
          categoryId: foodCategoryId(),
        ),
      );
      expect(result.isErr, isTrue);
      expect(result.error, isA<AccountNotFoundError>());
      expect(ledger.repository.data.transactions, isEmpty);
    });

    test('引用不存在的分类被拒绝', () async {
      final Result<Transaction> result = await ledger.repository.addTransaction(
        expense(
          id: 'tx_1',
          amountCents: 100,
          accountId: ledger.cashId,
          categoryId: 'nope',
        ),
      );
      expect(result.isErr, isTrue);
      expect(result.error, isA<CategoryNotFoundError>());
    });

    test('分类类型与交易类型不一致被拒绝', () async {
      final String salary = ledger.repository.data.categories
          .firstWhere((Category c) => c.name == '工资')
          .id;
      final Result<Transaction> result = await ledger.repository.addTransaction(
        expense(
          id: 'tx_1',
          amountCents: 100,
          accountId: ledger.cashId,
          categoryId: salary,
        ),
      );
      expect(result.isErr, isTrue);
      expect(result.error, isA<CategoryKindMismatchError>());
    });

    test('同一账户自转被拒绝', () async {
      final Result<Transaction> result = await ledger.repository.addTransaction(
        transfer(
          id: 'tx_1',
          amountCents: 100,
          fromAccountId: ledger.cashId,
          toAccountId: ledger.cashId,
        ),
      );
      expect(result.isErr, isTrue);
      expect(result.error, isA<SameAccountTransferError>());
    });

    test('编辑流水后金额更新', () async {
      final Result<Transaction> added = await ledger.repository.addTransaction(
        expense(
          id: 'tx_1',
          amountCents: 2500,
          accountId: ledger.cashId,
          categoryId: foodCategoryId(),
        ),
      );
      final Result<Transaction> updated =
          await ledger.repository.updateTransaction(
        added.value.copyWith(amountCents: 5000),
      );
      expect(updated.isOk, isTrue);
      expect(ledger.repository.data.transactions.single.amountCents, 5000);
    });

    test('编辑不存在的流水返回错误', () async {
      final Result<Transaction> result =
          await ledger.repository.updateTransaction(
        expense(
          id: 'missing',
          amountCents: 100,
          accountId: ledger.cashId,
          categoryId: foodCategoryId(),
        ),
      );
      expect(result.isErr, isTrue);
      expect(result.error, isA<NotFoundError>());
    });

    test('软删除后余额恢复，撤销后重新计入', () async {
      await ledger.repository.addTransaction(
        expense(
          id: 'tx_1',
          amountCents: 2500,
          accountId: ledger.cashId,
          categoryId: foodCategoryId(),
        ),
      );
      final Account cash = ledger.repository.data.accountById(ledger.cashId)!;

      await ledger.repository.deleteTransaction('tx_1');
      expect(ledger.repository.data.transactions.single.isDeleted, isTrue);
      expect(
        Selectors.accountBalance(cash, ledger.repository.data.transactions),
        0,
      );

      await ledger.repository.restoreTransaction('tx_1');
      expect(ledger.repository.data.transactions.single.isDeleted, isFalse);
      expect(
        Selectors.accountBalance(cash, ledger.repository.data.transactions),
        -2500,
      );
    });

    test('删除与恢复不存在的 id 返回错误', () async {
      expect(
        (await ledger.repository.deleteTransaction('nope')).error,
        isA<NotFoundError>(),
      );
      expect(
        (await ledger.repository.restoreTransaction('nope')).error,
        isA<NotFoundError>(),
      );
    });

    test('变更会通知监听者', () async {
      int notifications = 0;
      ledger.repository.addListener(() => notifications++);
      await ledger.repository.addTransaction(
        expense(
          id: 'tx_1',
          amountCents: 100,
          accountId: ledger.cashId,
          categoryId: foodCategoryId(),
        ),
      );
      expect(notifications, greaterThan(0));
    });
  });

  group('账户管理', () {
    test('新增账户并参与净资产', () async {
      final Result<Account> added = await ledger.repository.addAccount(
        account(id: 'acc_new', name: '工资卡', initialBalanceCents: 500000),
      );
      expect(added.isOk, isTrue);
      expect(added.value.sortOrder, greaterThan(0));
      expect(
        Selectors.netWorth(
          ledger.repository.data.accounts,
          ledger.repository.data.transactions,
        ),
        500000,
      );
    });

    test('重名账户被拒绝', () async {
      final Result<Account> result = await ledger.repository.addAccount(
        account(id: 'acc_new', name: '现金'),
      );
      expect(result.isErr, isTrue);
      expect(result.error, isA<DuplicateNameError>());
    });

    test('空名称被拒绝', () async {
      final Result<Account> result = await ledger.repository.addAccount(
        account(id: 'acc_new', name: '   '),
      );
      expect(result.error, isA<EmptyNameError>());
    });

    test('重命名自己不算重名', () async {
      final Account cash = ledger.repository.data.accounts.first;
      final Result<Account> result = await ledger.repository.updateAccount(
        cash.copyWith(name: '现金'),
      );
      expect(result.isOk, isTrue);
    });

    test('无流水账户可物理删除', () async {
      await ledger.repository.addAccount(
        account(id: 'acc_new', name: '临时卡'),
      );
      final Result<Unit> result =
          await ledger.repository.removeAccount('acc_new');
      expect(result.isOk, isTrue);
      expect(ledger.repository.data.accounts.length, 5);
    });

    test('有流水的账户不能物理删除', () async {
      await ledger.repository.addTransaction(
        expense(
          id: 'tx_1',
          amountCents: 100,
          accountId: ledger.cashId,
          categoryId: foodCategoryId(),
        ),
      );
      final Result<Unit> result =
          await ledger.repository.removeAccount(ledger.cashId);
      expect(result.isErr, isTrue);
      expect(result.error, isA<AccountInUseError>());
    });

    test('归档账户：余额不计入净资产，历史流水保留', () async {
      await ledger.repository.addTransaction(
        expense(
          id: 'tx_1',
          amountCents: 100,
          accountId: ledger.cashId,
          categoryId: foodCategoryId(),
        ),
      );
      final Result<Unit> result = await ledger.repository.deleteAccount(
        ledger.cashId,
      );
      expect(result.isOk, isTrue);
      expect(ledger.repository.data.transactions.length, 1);
      expect(
        ledger.repository.data.accountById(ledger.cashId)!.isArchived,
        isTrue,
      );
      // 归档账户余额为 -100，但不再计入净资产。
      expect(
        Selectors.netWorth(
          ledger.repository.data.accounts,
          ledger.repository.data.transactions,
        ),
        0,
      );
    });

    test('迁移流水到另一账户后删除原账户', () async {
      final String cashId = ledger.cashId;
      final Account bank = ledger.repository.data.activeAccounts
          .firstWhere((Account a) => a.kind == AccountKind.debitCard);
      await ledger.repository.addTransaction(
        expense(
          id: 'tx_1',
          amountCents: 100,
          accountId: cashId,
          categoryId: foodCategoryId(),
        ),
      );
      final Result<Unit> result = await ledger.repository.deleteAccount(
        cashId,
        strategy: AccountDeletionStrategy.migrate,
        migrateToAccountId: bank.id,
      );
      expect(result.isOk, isTrue);
      expect(ledger.repository.data.accountById(cashId), isNull);
      expect(ledger.repository.data.transactions.single.accountId, bank.id);
    });

    test('迁移到不存在的账户被拒绝', () async {
      final Result<Unit> result = await ledger.repository.deleteAccount(
        ledger.cashId,
        strategy: AccountDeletionStrategy.migrate,
        migrateToAccountId: 'nope',
      );
      expect(result.isErr, isTrue);
    });

    test('归档后可恢复', () async {
      await ledger.repository.deleteAccount(ledger.cashId);
      final Result<Unit> restored =
          await ledger.repository.restoreAccount(ledger.cashId);
      expect(restored.isOk, isTrue);
      expect(
        ledger.repository.data.accountById(ledger.cashId)!.isArchived,
        isFalse,
      );
    });
  });

  group('分类管理', () {
    test('新增自定义分类', () async {
      final Result<Category> added = await ledger.repository.addCategory(
        category(id: 'cat_custom', name: '宠物', kind: CategoryKind.expense),
      );
      expect(added.isOk, isTrue);
      expect(
        ledger.repository.data.activeCategories.any(
          (Category c) => c.name == '宠物',
        ),
        isTrue,
      );
    });

    test('重名分类被拒绝', () async {
      final Result<Category> result = await ledger.repository.addCategory(
        category(id: 'cat_x', name: '餐饮'),
      );
      expect(result.error, isA<DuplicateNameError>());
    });

    test('未被引用的分类被物理删除', () async {
      final String food = foodCategoryId();
      final Result<bool> result = await ledger.repository.deleteCategory(food);
      expect(result.isOk, isTrue);
      expect(result.value, isTrue, reason: '返回 true 表示已彻底删除');
      expect(
        ledger.repository.data.categories.any((Category c) => c.id == food),
        isFalse,
      );
    });

    test('被引用的分类只能归档', () async {
      final String food = foodCategoryId();
      await ledger.repository.addTransaction(
        expense(
          id: 'tx_1',
          amountCents: 100,
          accountId: ledger.cashId,
          categoryId: food,
        ),
      );
      final Result<bool> result = await ledger.repository.deleteCategory(food);
      expect(result.value, isFalse, reason: '返回 false 表示已归档');
      final Category category0 = ledger.repository.data.categoryById(food)!;
      expect(category0.isArchived, isTrue);
      expect(ledger.repository.data.transactions.length, 1);
    });

    test('归档分类可恢复', () async {
      final String food = foodCategoryId();
      await ledger.repository.addTransaction(
        expense(
          id: 'tx_1',
          amountCents: 100,
          accountId: ledger.cashId,
          categoryId: food,
        ),
      );
      await ledger.repository.deleteCategory(food);
      await ledger.repository.restoreCategory(food);
      expect(
        ledger.repository.data.categoryById(food)!.isArchived,
        isFalse,
      );
    });
  });

  group('偏好', () {
    test('偏好随账本持久化并在重启后读回', () async {
      final Result<Unit> saved =
          await ledger.repository.setPreference('currencySymbol', '￥');
      expect(saved.isOk, isTrue);
      expect(ledger.repository.preference('currencySymbol'), '￥');

      await ledger.repository.load();
      expect(ledger.repository.preference('currencySymbol'), '￥');
    });

    test('未设置的偏好返回 null', () {
      expect(ledger.repository.preference('nothing'), isNull);
    });
  });
}
