/// 账本数据仓库：内存快照 + 原子落盘 + 变更通知。
///
/// 所有写操作都遵循「校验 → 改内存 → 落盘 → 通知」的顺序；落盘失败时回滚内存，
/// 保证 UI 看到的状态与磁盘一致。
library;

import 'package:flutter/foundation.dart' hide Category;
import 'package:uuid/uuid.dart';

import '../core/result.dart';
import '../domain/account.dart';
import '../domain/category.dart';
import '../domain/enums.dart';
import '../domain/ledger_error.dart';
import '../domain/transaction.dart';
import 'ledger_data.dart';
import 'seed_data.dart';
import 'storage/ledger_storage.dart';

/// 标识符生成器，便于测试注入确定性 id。
typedef IdGenerator = String Function();

/// 时钟，便于测试固定「现在」。
typedef Clock = DateTime Function();

/// 账户删除时对历史流水的处理方式。
enum AccountDeletionStrategy {
  /// 保留流水，但把账户归档（历史仍可查看，不再计入余额与可选列表）。
  archive,

  /// 把该账户下的流水全部迁移到另一个账户。
  migrate,
}

/// 账本仓库。
final class LedgerRepository extends ChangeNotifier {
  /// 构造。
  LedgerRepository(
    this._storage, {
    IdGenerator? idGenerator,
    Clock? clock,
  })  : _newId = idGenerator ?? const Uuid().v4,
        _clock = clock ?? DateTime.now;

  final LedgerStorage _storage;
  final IdGenerator _newId;
  final Clock _clock;

  LedgerData _data = LedgerData.empty;
  bool _isReady = false;
  StorageReadResult? _lastRead;

  /// 当前内存快照。
  LedgerData get data => _data;

  /// 底层存储（导出文件、清空数据等运维操作使用）。
  LedgerStorage get storage => _storage;

  /// 是否已完成首次加载。
  bool get isReady => _isReady;

  /// 是否处于空账本状态（没有任何流水与自定义账户）。
  bool get isEmpty => _data.transactions.isEmpty;

  /// 最近一次读取的诊断信息（可能含损坏恢复告警）。
  StorageReadResult? get lastRead => _lastRead;

  /// 从磁盘加载账本；首次启动时写入默认账户与分类。
  Future<Result<Unit>> load() async {
    final Result<StorageReadResult> read = await _storage.read();
    if (read.isErr) {
      _isReady = true;
      notifyListeners();
      return Result<Unit>.err(read.error!);
    }
    _lastRead = read.value;
    LedgerData loaded = read.value.data;

    if (loaded.accounts.isEmpty && loaded.categories.isEmpty) {
      loaded = loaded.copyWith(
        accounts: seedAccounts(),
        categories: seedCategories(),
      );
      final Result<Unit> seeded = await _storage.write(loaded);
      if (seeded.isErr) {
        _data = loaded;
        _isReady = true;
        notifyListeners();
        return Result<Unit>.err(seeded.error!);
      }
    }

    _data = loaded;
    _isReady = true;
    notifyListeners();
    return const Result<Unit>.ok(Unit());
  }

  /// 丢弃内存中的告警提示（用户已确认）。
  void acknowledgeWarnings() {
    _lastRead = null;
    notifyListeners();
  }

  /// 生成新的实体 id。
  String newId([String prefix = '']) =>
      prefix.isEmpty ? _newId() : '${prefix}_${_newId()}';

  // ---------------------------------------------------------------- 交易

  /// 新增一笔交易。
  Future<Result<Transaction>> addTransaction(Transaction draft) async {
    final LedgerError? invalid = _validateDraft(draft);
    if (invalid != null) {
      return Result<Transaction>.err(invalid);
    }
    final DateTime now = _clock();
    final Transaction saved = draft.copyWith(
      createdAtUtc: draft.createdAtUtc ?? now,
      updatedAtUtc: now,
    );
    final List<Transaction> next = <Transaction>[..._data.transactions, saved];
    final LedgerError? failure =
        await _commit(_data.copyWith(transactions: next));
    if (failure != null) {
      return Result<Transaction>.err(failure);
    }
    return Result<Transaction>.ok(saved);
  }

  /// 修改一笔交易。
  Future<Result<Transaction>> updateTransaction(Transaction updated) async {
    final int index =
        _data.transactions.indexWhere((Transaction t) => t.id == updated.id);
    if (index < 0) {
      return const Result<Transaction>.err(NotFoundError('要修改的流水不存在'));
    }
    final LedgerError? invalid = _validateDraft(updated);
    if (invalid != null) {
      return Result<Transaction>.err(invalid);
    }
    final Transaction target = updated.copyWith(updatedAtUtc: _clock());
    final List<Transaction> next = List<Transaction>.of(_data.transactions)
      ..[index] = target;
    final LedgerError? failure =
        await _commit(_data.copyWith(transactions: next));
    if (failure != null) {
      return Result<Transaction>.err(failure);
    }
    return Result<Transaction>.ok(target);
  }

  /// 软删除一笔交易（可通过 [restoreTransaction] 撤销）。
  Future<Result<Unit>> deleteTransaction(String id) async {
    final int index =
        _data.transactions.indexWhere((Transaction t) => t.id == id);
    if (index < 0) {
      return const Result<Unit>.err(NotFoundError('要删除的流水不存在'));
    }
    final DateTime now = _clock();
    final List<Transaction> next = List<Transaction>.of(_data.transactions)
      ..[index] = _data.transactions[index].copyWith(
        deletedAtUtc: now,
        updatedAtUtc: now,
      );
    final LedgerError? failure =
        await _commit(_data.copyWith(transactions: next));
    return failure == null
        ? const Result<Unit>.ok(Unit())
        : Result<Unit>.err(failure);
  }

  /// 撤销软删除。
  Future<Result<Unit>> restoreTransaction(String id) async {
    final int index =
        _data.transactions.indexWhere((Transaction t) => t.id == id);
    if (index < 0) {
      return const Result<Unit>.err(NotFoundError('要恢复的流水不存在'));
    }
    final List<Transaction> next = List<Transaction>.of(_data.transactions)
      ..[index] = _data.transactions[index].copyWith(
        clearDeletedAt: true,
        updatedAtUtc: _clock(),
      );
    final LedgerError? failure =
        await _commit(_data.copyWith(transactions: next));
    return failure == null
        ? const Result<Unit>.ok(Unit())
        : Result<Unit>.err(failure);
  }

  // ---------------------------------------------------------------- 账户

  /// 新增账户。
  Future<Result<Account>> addAccount(Account draft) async {
    final LedgerError? invalid = _validateAccount(draft);
    if (invalid != null) {
      return Result<Account>.err(invalid);
    }
    final Account saved = draft.sortOrder == 0
        ? draft.copyWith(sortOrder: _nextAccountSortOrder())
        : draft;
    final LedgerError? failure = await _commit(
      _data.copyWith(accounts: <Account>[..._data.accounts, saved]),
    );
    if (failure != null) {
      return Result<Account>.err(failure);
    }
    return Result<Account>.ok(saved);
  }

  /// 修改账户。
  Future<Result<Account>> updateAccount(Account updated) async {
    final int index =
        _data.accounts.indexWhere((Account a) => a.id == updated.id);
    if (index < 0) {
      return const Result<Account>.err(NotFoundError('要修改的账户不存在'));
    }
    final LedgerError? invalid = _validateAccount(updated);
    if (invalid != null) {
      return Result<Account>.err(invalid);
    }
    final List<Account> next = List<Account>.of(_data.accounts)
      ..[index] = updated;
    final LedgerError? failure = await _commit(_data.copyWith(accounts: next));
    if (failure != null) {
      return Result<Account>.err(failure);
    }
    return Result<Account>.ok(updated);
  }

  /// 删除账户。
  ///
  /// * [AccountDeletionStrategy.archive]：归档账户，历史流水保留（推荐）。
  /// * [AccountDeletionStrategy.migrate]：把该账户下的流水迁移到 [migrateToAccountId]。
  Future<Result<Unit>> deleteAccount(
    String id, {
    AccountDeletionStrategy strategy = AccountDeletionStrategy.archive,
    String? migrateToAccountId,
  }) async {
    final Account? account = _data.accountById(id);
    if (account == null) {
      return const Result<Unit>.err(NotFoundError('要删除的账户不存在'));
    }
    switch (strategy) {
      case AccountDeletionStrategy.archive:
        return _archiveAccount(account);
      case AccountDeletionStrategy.migrate:
        final String? target = migrateToAccountId;
        if (target == null || target == id) {
          return const Result<Unit>.err(
            InvalidTransferError('请选择另一个账户作为流水的迁移目标'),
          );
        }
        if (_data.accountById(target) == null) {
          return Result<Unit>.err(AccountNotFoundError(target));
        }
        return _migrateAccount(account, target);
    }
  }

  /// 仅当账户没有任何关联流水时，才物理删除该账户。
  ///
  /// 用于「删除刚建错、还没记过账的账户」这一常见场景；有流水时请用
  /// [deleteAccount] 选择归档或迁移。
  Future<Result<Unit>> removeAccount(String id) async {
    final Account? account = _data.accountById(id);
    if (account == null) {
      return const Result<Unit>.err(NotFoundError('要删除的账户不存在'));
    }
    final int related = _data.transactionCountForAccount(id);
    if (related > 0) {
      return Result<Unit>.err(AccountInUseError(id, related));
    }
    final List<Account> next =
        _data.accounts.where((Account a) => a.id != id).toList();
    final LedgerError? failure = await _commit(_data.copyWith(accounts: next));
    return failure == null
        ? const Result<Unit>.ok(Unit())
        : Result<Unit>.err(failure);
  }

  Future<Result<Unit>> _archiveAccount(Account account) async {
    final int index =
        _data.accounts.indexWhere((Account a) => a.id == account.id);
    final List<Account> next = List<Account>.of(_data.accounts)
      ..[index] = account.copyWith(archivedAt: _clock());
    final LedgerError? failure = await _commit(_data.copyWith(accounts: next));
    return failure == null
        ? const Result<Unit>.ok(Unit())
        : Result<Unit>.err(failure);
  }

  Future<Result<Unit>> _migrateAccount(Account from, String toId) async {
    final List<Transaction> migrated = _data.transactions.map((Transaction t) {
      final bool isSource = t.accountId == from.id;
      final bool isTarget = t.toAccountId == from.id;
      if (!isSource && !isTarget) {
        return t;
      }
      if (t.kind == TxKind.transfer && isSource && isTarget) {
        // 自转在任何校验下都不合法，保留原样交给 sanitize 处理。
        return t;
      }
      return t.copyWith(
        accountId: isSource ? toId : t.accountId,
        toAccountId: isSource ? t.toAccountId : toId,
        updatedAtUtc: _clock(),
      );
    }).toList();

    final List<Account> accounts =
        _data.accounts.where((Account a) => a.id != from.id).toList();
    final LedgerError? failure = await _commit(
      LedgerData(
        accounts: accounts,
        categories: _data.categories,
        transactions: migrated,
      ),
    );
    return failure == null
        ? const Result<Unit>.ok(Unit())
        : Result<Unit>.err(failure);
  }

  /// 恢复归档账户。
  Future<Result<Unit>> restoreAccount(String id) async {
    final int index = _data.accounts.indexWhere((Account a) => a.id == id);
    if (index < 0) {
      return const Result<Unit>.err(NotFoundError('账户不存在'));
    }
    final List<Account> next = List<Account>.of(_data.accounts)
      ..[index] = _data.accounts[index].copyWith(clearArchivedAt: true);
    final LedgerError? failure = await _commit(_data.copyWith(accounts: next));
    return failure == null
        ? const Result<Unit>.ok(Unit())
        : Result<Unit>.err(failure);
  }

  // ---------------------------------------------------------------- 分类

  /// 新增分类。
  Future<Result<Category>> addCategory(Category draft) async {
    final LedgerError? invalid = _validateCategory(draft);
    if (invalid != null) {
      return Result<Category>.err(invalid);
    }
    final LedgerError? failure = await _commit(
      _data.copyWith(categories: <Category>[..._data.categories, draft]),
    );
    if (failure != null) {
      return Result<Category>.err(failure);
    }
    return Result<Category>.ok(draft);
  }

  /// 修改分类。
  Future<Result<Category>> updateCategory(Category updated) async {
    final int index =
        _data.categories.indexWhere((Category c) => c.id == updated.id);
    if (index < 0) {
      return const Result<Category>.err(NotFoundError('要修改的分类不存在'));
    }
    final LedgerError? invalid = _validateCategory(updated);
    if (invalid != null) {
      return Result<Category>.err(invalid);
    }
    final List<Category> next = List<Category>.of(_data.categories)
      ..[index] = updated;
    final LedgerError? failure =
        await _commit(_data.copyWith(categories: next));
    if (failure != null) {
      return Result<Category>.err(failure);
    }
    return Result<Category>.ok(updated);
  }

  /// 删除分类：未被引用时物理删除，被引用时改为归档。
  Future<Result<bool>> deleteCategory(String id) async {
    final int index = _data.categories.indexWhere((Category c) => c.id == id);
    if (index < 0) {
      return const Result<bool>.err(NotFoundError('要删除的分类不存在'));
    }
    final int used = _data.transactionCountForCategory(id);
    if (used > 0) {
      final List<Category> archived = List<Category>.of(_data.categories)
        ..[index] = _data.categories[index].copyWith(archivedAt: _clock());
      final LedgerError? failure =
          await _commit(_data.copyWith(categories: archived));
      if (failure != null) {
        return Result<bool>.err(failure);
      }
      return const Result<bool>.ok(false);
    }
    final List<Category> next =
        _data.categories.where((Category c) => c.id != id).toList();
    final LedgerError? failure =
        await _commit(_data.copyWith(categories: next));
    if (failure != null) {
      return Result<bool>.err(failure);
    }
    return const Result<bool>.ok(true);
  }

  /// 恢复归档分类。
  Future<Result<Unit>> restoreCategory(String id) async {
    final int index = _data.categories.indexWhere((Category c) => c.id == id);
    if (index < 0) {
      return const Result<Unit>.err(NotFoundError('分类不存在'));
    }
    final List<Category> next = List<Category>.of(_data.categories)
      ..[index] = _data.categories[index].copyWith(clearArchivedAt: true);
    final LedgerError? failure =
        await _commit(_data.copyWith(categories: next));
    return failure == null
        ? const Result<Unit>.ok(Unit())
        : Result<Unit>.err(failure);
  }

  // ---------------------------------------------------------------- 导入导出

  /// 用给定数据整体替换当前账本（导入、清空均走这里）。
  Future<Result<Unit>> replaceAll(LedgerData replacement) async {
    final LedgerError? failure = await _commit(replacement);
    return failure == null
        ? const Result<Unit>.ok(Unit())
        : Result<Unit>.err(failure);
  }

  /// 合并导入：按 id 覆盖同 id 记录，其余追加。
  Future<Result<Unit>> mergeIn(LedgerData incoming) async {
    final Map<String, Account> accounts = <String, Account>{
      for (final Account a in _data.accounts) a.id: a,
      for (final Account a in incoming.accounts) a.id: a,
    };
    final Map<String, Category> categories = <String, Category>{
      for (final Category c in _data.categories) c.id: c,
      for (final Category c in incoming.categories) c.id: c,
    };
    final Map<String, Transaction> transactions = <String, Transaction>{
      for (final Transaction t in _data.transactions) t.id: t,
      for (final Transaction t in incoming.transactions) t.id: t,
    };
    final LedgerData merged = LedgerData(
      accounts: accounts.values.toList(),
      categories: categories.values.toList(),
      transactions: transactions.values.toList(),
    );
    final ({LedgerData data, List<String> warnings}) cleaned =
        merged.sanitize();
    return replaceAll(cleaned.data);
  }

  // ---------------------------------------------------------------- 偏好

  /// 读取一个偏好值。
  String? preference(String key) => _data.preferences[key];

  /// 写入一个偏好值。
  Future<Result<Unit>> setPreference(String key, String value) async {
    final Map<String, String> next = <String, String>{
      ..._data.preferences,
      key: value,
    };
    final LedgerError? failure =
        await _commit(_data.copyWith(preferences: next));
    return failure == null
        ? const Result<Unit>.ok(Unit())
        : Result<Unit>.err(failure);
  }

  // ---------------------------------------------------------------- 内部

  Future<LedgerError?> _commit(LedgerData next) async {
    final LedgerData previous = _data;
    _data = next;
    final Result<Unit> written = await _storage.write(next);
    if (written.isErr) {
      _data = previous;
      return written.error;
    }
    notifyListeners();
    return null;
  }

  LedgerError? _validateDraft(Transaction draft) {
    final LedgerError? invalid = draft.validate();
    if (invalid != null) {
      return invalid;
    }
    if (_data.accountById(draft.accountId) == null) {
      return AccountNotFoundError(draft.accountId);
    }
    final String? to = draft.toAccountId;
    if (to != null && _data.accountById(to) == null) {
      return AccountNotFoundError(to);
    }
    final String? categoryId = draft.categoryId;
    if (categoryId != null) {
      final Category? category = _data.categoryById(categoryId);
      if (category == null) {
        return CategoryNotFoundError(categoryId);
      }
      if (category.kind.asTxKind != draft.kind) {
        return CategoryKindMismatchError(category.kind, draft.kind);
      }
    }
    return null;
  }

  LedgerError? _validateAccount(Account account) {
    if (account.name.trim().isEmpty) {
      return const EmptyNameError();
    }
    if (_data.hasAccountNamed(account.name.trim(), exceptId: account.id)) {
      return DuplicateNameError(account.name.trim());
    }
    return null;
  }

  LedgerError? _validateCategory(Category category) {
    if (category.name.trim().isEmpty) {
      return const EmptyNameError();
    }
    if (_data.hasCategoryNamed(category.name.trim(), exceptId: category.id)) {
      return DuplicateNameError(category.name.trim());
    }
    final String? parentId = category.parentId;
    if (parentId != null) {
      final Category? parent = _data.categoryById(parentId);
      if (parent == null) {
        return CategoryNotFoundError(parentId);
      }
      if (parent.kind != category.kind) {
        return CategoryKindMismatchError(parent.kind, category.kind.asTxKind!);
      }
    }
    return null;
  }

  int _nextAccountSortOrder() {
    if (_data.accounts.isEmpty) {
      return 0;
    }
    return _data.accounts
            .map((Account a) => a.sortOrder)
            .reduce((int a, int b) => a > b ? a : b) +
        1;
  }
}
