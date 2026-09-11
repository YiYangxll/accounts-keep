/// 仓库失败路径测试：落盘失败必须回滚内存态、不得丢数据。
library;

import 'dart:io';

import 'package:accounts_keep/core/result.dart';
import 'package:accounts_keep/data/ledger_data.dart';
import 'package:accounts_keep/data/ledger_repository.dart';
import 'package:accounts_keep/data/storage/ledger_storage.dart';
import 'package:accounts_keep/domain/account.dart';
import 'package:accounts_keep/domain/category.dart';
import 'package:accounts_keep/domain/enums.dart';
import 'package:accounts_keep/domain/ledger_error.dart';
import 'package:accounts_keep/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

/// 可控失败的存储：用于验证写失败时的回滚与错误上报。
///
/// 通过继承 [LedgerStorage] 并覆写关键方法实现，因此生产类刻意未声明为 `final`。
final class FailingStorage extends LedgerStorage {
  /// 构造。
  FailingStorage(this._inner) : super(documentsDirectoryProvider: _never);

  final LedgerStorage _inner;

  static Future<Directory> _never() =>
      throw StateError('FailingStorage 不应直接使用父类的文件能力');

  /// 为 true 时 [write] 一律失败。
  bool failWrite = false;

  /// 为 true 时 [read] 一律失败。
  bool failRead = false;

  /// 为 true 时 [deleteAll] 失败。
  bool failDeleteAll = false;

  /// 记录 write 调用次数。
  int writeCount = 0;

  @override
  String get directoryName => _inner.directoryName;

  @override
  String get fileName => _inner.fileName;

  @override
  Future<Result<StorageReadResult>> read() async {
    if (failRead) {
      return const Result<StorageReadResult>.err(
        StorageError('模拟读取失败'),
      );
    }
    return _inner.read();
  }

  @override
  Future<Result<Unit>> write(LedgerData data) async {
    writeCount += 1;
    if (failWrite) {
      return const Result<Unit>.err(StorageError('模拟写入失败'));
    }
    return _inner.write(data);
  }

  @override
  Future<Result<Unit>> deleteAll() async {
    if (failDeleteAll) {
      return const Result<Unit>.err(StorageError('模拟清空失败'));
    }
    return _inner.deleteAll();
  }

  @override
  Future<Result<Directory>> exportDirectory() => _inner.exportDirectory();

  @override
  Future<Result<File>> writeExport(String fileName, String content) =>
      _inner.writeExport(fileName, content);

  @override
  Result<LedgerData> decodeForTest(String raw) => _inner.decodeForTest(raw);
}

void main() {
  late Directory dir;
  late FailingStorage storage;
  late LedgerRepository repository;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('repo_fail_test_');
    storage = FailingStorage(
      LedgerStorage(documentsDirectoryProvider: () async => dir),
    );
    repository = LedgerRepository(storage, clock: fixedClock);
    await repository.load();
  });

  tearDown(() async {
    repository.dispose();
    for (int attempt = 0; attempt < 5; attempt++) {
      if (!dir.existsSync()) {
        return;
      }
      try {
        dir.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    }
  });

  String foodId() =>
      repository.data.categories.firstWhere((Category c) => c.name == '餐饮').id;

  group('读取失败', () {
    test('load 失败时仍给出默认数据并标记已就绪', () async {
      final TestLedger fresh = await TestLedger.create();
      addTearDown(fresh.dispose);
      final FailingStorage broken = FailingStorage(fresh.storage)
        ..failRead = true;
      final LedgerRepository repo = LedgerRepository(broken, clock: fixedClock);

      final Result<Unit> result = await repo.load();
      expect(result.isErr, isTrue);
      expect(result.error, isA<StorageError>());
      expect(repo.isReady, isTrue);
      expect(repo.data.transactions, isEmpty);
      repo.dispose();
    });
  });

  group('写入失败回滚', () {
    test('新增流水失败时不写内存', () async {
      storage.failWrite = true;
      final Result<Transaction> result = await repository.addTransaction(
        expense(
          id: 'tx_1',
          amountCents: 100,
          accountId: repository.data.accounts.first.id,
          categoryId: foodId(),
        ),
      );
      expect(result.isErr, isTrue);
      expect(result.error, isA<StorageError>());
      expect(repository.data.transactions, isEmpty);
    });

    test('已有数据不会因为一次写失败而丢失', () async {
      final String cashId = repository.data.accounts.first.id;
      await repository.addTransaction(
        expense(
          id: 'tx_ok',
          amountCents: 500,
          accountId: cashId,
          categoryId: foodId(),
        ),
      );
      expect(repository.data.transactions.length, 1);

      storage.failWrite = true;
      final Result<Transaction> failed = await repository.addTransaction(
        expense(
          id: 'tx_fail',
          amountCents: 999,
          accountId: cashId,
          categoryId: foodId(),
        ),
      );
      expect(failed.isErr, isTrue);
      // 内存里仍是那一条成功写入的记录。
      expect(repository.data.transactions.length, 1);
      expect(repository.data.transactions.single.id, 'tx_ok');

      // 磁盘上也只应读到那一条。
      storage.failWrite = false;
      await repository.load();
      expect(repository.data.transactions.length, 1);
      expect(repository.data.transactions.single.id, 'tx_ok');
    });

    test('编辑失败时保留原值', () async {
      final String cashId = repository.data.accounts.first.id;
      final Result<Transaction> added = await repository.addTransaction(
        expense(
          id: 'tx_1',
          amountCents: 500,
          accountId: cashId,
          categoryId: foodId(),
        ),
      );
      storage.failWrite = true;
      final Result<Transaction> updated = await repository.updateTransaction(
        added.value.copyWith(amountCents: 9999),
      );
      expect(updated.isErr, isTrue);
      expect(repository.data.transactions.single.amountCents, 500);
    });

    test('删除与恢复失败时报错且状态不变', () async {
      final String cashId = repository.data.accounts.first.id;
      await repository.addTransaction(
        expense(
          id: 'tx_1',
          amountCents: 500,
          accountId: cashId,
          categoryId: foodId(),
        ),
      );
      storage.failWrite = true;
      expect(
        (await repository.deleteTransaction('tx_1')).error,
        isA<StorageError>(),
      );
      expect(repository.data.transactions.single.isDeleted, isFalse);

      storage.failWrite = false;
      await repository.deleteTransaction('tx_1');
      expect(repository.data.transactions.single.isDeleted, isTrue);
      storage.failWrite = true;
      expect(
        (await repository.restoreTransaction('tx_1')).error,
        isA<StorageError>(),
      );
      expect(repository.data.transactions.single.isDeleted, isTrue);
    });

    test('账户写失败时回滚', () async {
      storage.failWrite = true;
      final Result<Account> added = await repository.addAccount(
        account(id: 'acc_x', name: '新账户'),
      );
      expect(added.isErr, isTrue);
      expect(repository.data.accountById('acc_x'), isNull);

      final Account cash = repository.data.accounts.first;
      final Result<Account> updated =
          await repository.updateAccount(cash.copyWith(name: '改名'));
      expect(updated.isErr, isTrue);
      expect(repository.data.accounts.first.name, '现金');
    });

    test('分类写失败时回滚', () async {
      storage.failWrite = true;
      final Result<Category> added = await repository.addCategory(
        category(id: 'cat_x', name: '新分类'),
      );
      expect(added.isErr, isTrue);
      expect(repository.data.categoryById('cat_x'), isNull);

      final Result<bool> deleted = await repository.deleteCategory(foodId());
      expect(deleted.isErr, isTrue);
      expect(repository.data.categoryById(foodId()), isNotNull);
    });

    test('归档 / 恢复账户失败时报错', () async {
      final String cashId = repository.data.accounts.first.id;
      storage.failWrite = true;
      expect(
        (await repository.deleteAccount(cashId)).error,
        isA<StorageError>(),
      );
      expect(repository.data.accountById(cashId)!.isArchived, isFalse);

      storage.failWrite = false;
      await repository.deleteAccount(cashId);
      storage.failWrite = true;
      expect(
        (await repository.restoreAccount(cashId)).error,
        isA<StorageError>(),
      );
      expect(repository.data.accountById(cashId)!.isArchived, isTrue);
    });

    test('迁移流水失败时账户与流水都保持原样', () async {
      final List<Account> accounts = repository.data.activeAccounts;
      final Account cash = accounts.firstWhere(
        (Account a) => a.kind == AccountKind.cash,
      );
      final Account bank = accounts.firstWhere(
        (Account a) => a.kind == AccountKind.debitCard,
      );
      await repository.addTransaction(
        expense(
          id: 'tx_1',
          amountCents: 100,
          accountId: cash.id,
          categoryId: foodId(),
        ),
      );

      storage.failWrite = true;
      final Result<Unit> result = await repository.deleteAccount(
        cash.id,
        strategy: AccountDeletionStrategy.migrate,
        migrateToAccountId: bank.id,
      );
      expect(result.isErr, isTrue);
      expect(repository.data.accountById(cash.id), isNotNull);
      expect(repository.data.transactions.single.accountId, cash.id);
    });

    test('替换与合并失败时报错', () async {
      storage.failWrite = true;
      final Result<Unit> replaced =
          await repository.replaceAll(const LedgerData());
      expect(replaced.isErr, isTrue);

      final Result<Unit> merged = await repository.mergeIn(
        LedgerData(accounts: <Account>[account(id: 'acc_y', name: 'Y')]),
      );
      expect(merged.isErr, isTrue);
      expect(repository.data.accountById('acc_y'), isNull);
    });

    test('偏好写失败时报错且不改内存', () async {
      storage.failWrite = true;
      final Result<Unit> result =
          await repository.setPreference('themeMode', 'dark');
      expect(result.isErr, isTrue);
      expect(repository.preference('themeMode'), isNull);
    });
  });

  group('合并导入', () {
    test('同 id 覆盖、新 id 追加', () async {
      final String cashId = repository.data.accounts.first.id;
      await repository.addTransaction(
        expense(
          id: 'tx_1',
          amountCents: 100,
          accountId: cashId,
          categoryId: foodId(),
        ),
      );

      final LedgerData incoming = LedgerData(
        accounts: repository.data.accounts,
        categories: repository.data.categories,
        transactions: <Transaction>[
          expense(
            id: 'tx_1',
            amountCents: 777,
            accountId: cashId,
            categoryId: foodId(),
          ),
          expense(
            id: 'tx_2',
            amountCents: 300,
            accountId: cashId,
            categoryId: foodId(),
          ),
        ],
      );
      final Result<Unit> merged = await repository.mergeIn(incoming);
      expect(merged.isOk, isTrue);
      expect(repository.data.transactions.length, 2);
      expect(
        repository.data.transactionById('tx_1')!.amountCents,
        777,
        reason: '同 id 以导入数据为准',
      );
    });

    test('合并会剔除引用缺失账户的流水', () async {
      final LedgerData incoming = LedgerData(
        accounts: repository.data.accounts,
        categories: repository.data.categories,
        transactions: <Transaction>[
          expense(
            id: 'tx_bad',
            amountCents: 100,
            accountId: 'acc_不存在',
            categoryId: foodId(),
          ),
        ],
      );
      final Result<Unit> merged = await repository.mergeIn(incoming);
      expect(merged.isOk, isTrue);
      expect(repository.data.transactionById('tx_bad'), isNull);
    });
  });

  group('替换导入与清空', () {
    test('replaceAll 完整替换数据', () async {
      final Result<Unit> replaced = await repository.replaceAll(
        LedgerData(
          accounts: <Account>[account(id: 'acc_only', name: '唯一账户')],
          categories: <Category>[category(id: 'cat_only', name: '唯一分类')],
        ),
      );
      expect(replaced.isOk, isTrue);
      expect(repository.data.accounts.length, 1);
      expect(repository.data.accounts.single.name, '唯一账户');
      expect(repository.data.categories.length, 1);
      expect(repository.data.transactions, isEmpty);
    });

    test('清空后重新加载会恢复默认账户与分类', () async {
      await repository.addTransaction(
        expense(
          id: 'tx_1',
          amountCents: 100,
          accountId: repository.data.accounts.first.id,
          categoryId: foodId(),
        ),
      );
      final Result<Unit> cleared = await repository.storage.deleteAll();
      expect(cleared.isOk, isTrue);
      final Result<Unit> reloaded = await repository.load();
      expect(reloaded.isOk, isTrue);
      expect(repository.data.transactions, isEmpty);
      expect(repository.data.accounts.length, 5);
      expect(repository.data.categories.length, 16);
    });
  });
}
