/// 账本顶层数据结构与序列化。
library;

import 'dart:convert';

import '../core/json_x.dart';
import '../domain/account.dart';
import '../domain/category.dart';
import '../domain/enums.dart';
import '../domain/ledger_error.dart';
import '../domain/transaction.dart';

/// 当前数据版本。任何不兼容的结构变更都必须递增该值并补充迁移逻辑。
const int kLedgerSchemaVersion = 1;

/// 整个账本的内存态数据。
final class LedgerData {
  /// 构造。
  const LedgerData({
    this.accounts = const <Account>[],
    this.categories = const <Category>[],
    this.transactions = const <Transaction>[],
    this.preferences = const <String, String>{},
  });

  /// 空账本。
  static const LedgerData empty = LedgerData();

  /// 从 JSON 还原。
  factory LedgerData.fromJson(Map<String, Object?> json) => LedgerData(
        accounts: parseObjectList<Account>(
            json.optionalList('accounts'), Account.fromJson),
        categories: parseObjectList<Category>(
          json.optionalList('categories'),
          Category.fromJson,
        ),
        transactions: parseObjectList<Transaction>(
          json.optionalList('transactions'),
          Transaction.fromJson,
        ),
        preferences: _parsePreferences(json.optionalMap('preferences')),
      );

  /// 所有账户（含归档）。
  final List<Account> accounts;

  /// 所有分类（含归档）。
  final List<Category> categories;

  /// 所有交易（含软删除）。
  final List<Transaction> transactions;

  /// 界面偏好（主题、货币符号等），随账本一起持久化。
  final Map<String, String> preferences;

  /// 未归档账户。
  List<Account> get activeAccounts =>
      accounts.where((Account a) => !a.isArchived).toList();

  /// 未归档分类。
  List<Category> get activeCategories =>
      categories.where((Category c) => !c.isArchived).toList();

  /// 未删除交易。
  List<Transaction> get activeTransactions =>
      transactions.where((Transaction t) => !t.isDeleted).toList();

  /// 按 id 查找账户。
  Account? accountById(String id) {
    for (final Account a in accounts) {
      if (a.id == id) {
        return a;
      }
    }
    return null;
  }

  /// 按 id 查找分类。
  Category? categoryById(String id) {
    for (final Category c in categories) {
      if (c.id == id) {
        return c;
      }
    }
    return null;
  }

  /// 按 id 查找交易。
  Transaction? transactionById(String id) {
    for (final Transaction t in transactions) {
      if (t.id == id) {
        return t;
      }
    }
    return null;
  }

  /// 统计某账户关联的流水条数（含软删除记录，因为撤销恢复仍需该账户）。
  int transactionCountForAccount(String accountId) => transactions
      .where((Transaction t) =>
          t.accountId == accountId || t.toAccountId == accountId)
      .length;

  /// 统计某分类被引用的流水条数。
  int transactionCountForCategory(String categoryId) =>
      transactions.where((Transaction t) => t.categoryId == categoryId).length;

  /// 是否存在该名称的账户（可指定忽略的 id 以便重命名）。
  bool hasAccountNamed(String name, {String? exceptId}) => accounts.any(
        (Account a) => a.name == name && a.id != exceptId,
      );

  /// 是否存在该类型下的同名分类。
  bool hasCategoryNamed(String name, {String? exceptId}) => categories.any(
        (Category c) => c.name == name && c.id != exceptId,
      );

  /// 复制并覆盖部分字段。
  LedgerData copyWith({
    List<Account>? accounts,
    List<Category>? categories,
    List<Transaction>? transactions,
    Map<String, String>? preferences,
  }) {
    return LedgerData(
      accounts: accounts ?? this.accounts,
      categories: categories ?? this.categories,
      transactions: transactions ?? this.transactions,
      preferences: preferences ?? this.preferences,
    );
  }

  /// 序列化为 JSON（仅账本内容，不带版本信封）。
  Map<String, Object?> toJson() => <String, Object?>{
        'accounts': accounts.map((Account a) => a.toJson()).toList(),
        'categories': categories.map((Category c) => c.toJson()).toList(),
        'transactions':
            transactions.map((Transaction t) => t.toJson()).toList(),
        'preferences': preferences,
      };

  /// 序列化为带版本号的完整信封。
  ///
  /// 落盘与导出**共用**这一格式，保证「磁盘上的数据」与「导出的备份」
  /// 结构完全一致，避免两条路径各写一种结构。
  Map<String, Object?> toEnvelopeJson({DateTime? exportedAtUtc}) {
    return <String, Object?>{
      'schemaVersion': kLedgerSchemaVersion,
      'exportedAtUtc':
          (exportedAtUtc ?? DateTime.now()).toUtc().toIso8601String(),
      'app': <String, Object?>{
        'name': 'accounts_keep',
        'version': '1.0.0',
      },
      'counts': <String, Object?>{
        'accounts': accounts.length,
        'categories': categories.length,
        'transactions': transactions.length,
      },
      'data': toJson(),
    };
  }

  /// 编码为可落盘的 JSON 文本（缩进便于人工排查）。
  String encode({bool pretty = true}) {
    final Map<String, Object?> envelope = toEnvelopeJson();
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(envelope)
        : jsonEncode(envelope);
  }

  /// 保证引用的完整性：剔除孤立引用，返回清洗后的数据与警告列表。
  ///
  /// 用于读取旧数据或导入外部数据后自愈，避免 UI 因悬空引用出错。
  ({LedgerData data, List<String> warnings}) sanitize() {
    final Set<String> accountIds = accounts.map((Account a) => a.id).toSet();
    final Map<String, Category> categoryById = <String, Category>{
      for (final Category c in categories) c.id: c,
    };
    final List<String> warnings = <String>[];
    final List<Transaction> kept = <Transaction>[];
    final Set<String> seenIds = <String>{};

    for (final Transaction t in transactions) {
      if (!seenIds.add(t.id)) {
        warnings.add('忽略重复 id 的流水：${t.id}');
        continue;
      }
      final LedgerError? invalid = t.validate();
      if (invalid != null) {
        warnings.add('忽略非法流水 ${t.id}：${invalid.message}');
        continue;
      }
      if (!accountIds.contains(t.accountId)) {
        warnings.add('忽略引用缺失账户的流水 ${t.id}');
        continue;
      }
      final String? to = t.toAccountId;
      if (to != null && !accountIds.contains(to)) {
        warnings.add('忽略引用缺失转入账户的流水 ${t.id}');
        continue;
      }
      final String? categoryId = t.categoryId;
      if (categoryId != null) {
        final Category? category = categoryById[categoryId];
        if (category == null) {
          warnings.add('忽略引用缺失分类的流水 ${t.id}');
          continue;
        }
        if (category.kind.asTxKind != t.kind) {
          warnings.add('忽略分类类型不匹配的流水 ${t.id}');
          continue;
        }
      }
      kept.add(t);
    }

    final Set<String> categoryIds = categoryById.keys.toSet();
    final List<Category> keptCategories = categories
        .where((Category c) =>
            c.parentId == null || categoryIds.contains(c.parentId))
        .toList();
    if (keptCategories.length != categories.length) {
      warnings
          .add('忽略了 ${categories.length - keptCategories.length} 个上级分类缺失的分类');
    }

    return (
      data: LedgerData(
        accounts: accounts,
        categories: keptCategories,
        transactions: kept,
        preferences: preferences,
      ),
      warnings: warnings,
    );
  }
}

Map<String, String> _parsePreferences(Map<String, Object?>? raw) {
  if (raw == null) {
    return const <String, String>{};
  }
  final Map<String, String> result = <String, String>{};
  raw.forEach((String key, Object? value) {
    if (value is String) {
      result[key] = value;
    }
  });
  return result;
}
