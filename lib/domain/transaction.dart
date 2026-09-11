/// 交易（流水）模型：收入、支出、转账共用一种结构，由 [TxKind] 区分。
library;

import '../core/date_x.dart';
import '../core/json_x.dart';
import '../core/money.dart';
import 'enums.dart';
import 'ledger_error.dart';

/// 交易的一个分项（MVP 仅预留结构，UI 暂不启用）。
final class TxSplit {
  /// 构造。
  const TxSplit({
    required this.categoryId,
    required this.amountCents,
    this.note,
  });

  /// 从 JSON 还原。
  factory TxSplit.fromJson(Map<String, Object?> json) => TxSplit(
        categoryId: json.requireString('categoryId'),
        amountCents: json.requireInt('amountCents'),
        note: json.optionalString('note'),
      );

  /// 分项所属分类。
  final String categoryId;

  /// 分项金额（分，恒为正）。
  final int amountCents;

  /// 分项备注。
  final String? note;

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'categoryId': categoryId,
        'amountCents': amountCents,
        'note': note,
      };

  @override
  bool operator ==(Object other) =>
      other is TxSplit &&
      other.categoryId == categoryId &&
      other.amountCents == amountCents &&
      other.note == note;

  @override
  int get hashCode => Object.hash(categoryId, amountCents, note);
}

/// 一笔交易。
final class Transaction {
  /// 构造。
  const Transaction({
    required this.id,
    required this.kind,
    required this.amountCents,
    required this.accountId,
    required this.occurredAtUtc,
    required this.utcOffsetMinutes,
    this.toAccountId,
    this.feeCents = 0,
    this.categoryId,
    this.note,
    this.payee,
    this.tag,
    this.splits = const <TxSplit>[],
    this.createdAtUtc,
    this.updatedAtUtc,
    this.deletedAtUtc,
  });

  /// 从持久化 JSON 还原。任何不满足不变量的数据都会抛出 [LedgerError]。
  factory Transaction.fromJson(Map<String, Object?> json) {
    final String rawKind = json.requireString('kind');
    final TxKind? kind = TxKindLabel.tryParse(rawKind);
    if (kind == null) {
      throw UnknownEnumValueError('kind', rawKind);
    }
    return Transaction(
      id: json.requireString('id'),
      kind: kind,
      amountCents: json.requireInt('amountCents'),
      accountId: json.requireString('accountId'),
      toAccountId: json.optionalString('toAccountId'),
      feeCents: json.optionalInt('feeCents') ?? 0,
      categoryId: json.optionalString('categoryId'),
      occurredAtUtc: json.requireDateTime('occurredAtUtc'),
      utcOffsetMinutes: json.optionalInt('utcOffsetMinutes') ?? 0,
      note: json.optionalString('note'),
      payee: json.optionalString('payee'),
      tag: json.optionalString('tag'),
      splits: parseObjectList<TxSplit>(
          json.optionalList('splits'), TxSplit.fromJson),
      createdAtUtc: json.optionalDateTime('createdAtUtc'),
      updatedAtUtc: json.optionalDateTime('updatedAtUtc'),
      deletedAtUtc: json.optionalDateTime('deletedAtUtc'),
    );
  }

  /// 唯一标识。
  final String id;

  /// 交易类型。
  final TxKind kind;

  /// 金额（分，恒为正）。
  final int amountCents;

  /// 转出账户（支出、收入即发生账户）。
  final String accountId;

  /// 转入账户；仅转账使用。
  final String? toAccountId;

  /// 转账手续费（分，非负）。
  final int feeCents;

  /// 分类 id；转账为 null。
  final String? categoryId;

  /// 发生时间（UTC 瞬时）。
  final DateTime occurredAtUtc;

  /// 记账时的本地时区偏移（分钟），用于还原用户当时的日期。
  final int utcOffsetMinutes;

  /// 备注。
  final String? note;

  /// 交易对象（商户/对方）。
  final String? payee;

  /// 标签（预留）。
  final String? tag;

  /// 分项明细（预留）。
  final List<TxSplit> splits;

  /// 创建时间。
  final DateTime? createdAtUtc;

  /// 最后修改时间。
  final DateTime? updatedAtUtc;

  /// 软删除时间；非空表示已删除，可撤销恢复。
  final DateTime? deletedAtUtc;

  /// 发生时间按记账时区的本地时间，用于展示日期与月份归属。
  DateTime get occurredAtLocal =>
      occurredAtUtc.add(Duration(minutes: utcOffsetMinutes)).toLocal();

  /// 发生时间按记账时区还原的「墙上时间」。
  ///
  /// 语义说明（使用本字段时最容易踩的坑）：
  /// * 它表达「用户当时看到的日期时间」，是**组件语义**而非瞬时语义；
  /// * 返回值以 UTC 标记承载，因此**不要**用 `millisecondsSinceEpoch` 或与
  ///   `DateTime(...)` 直接比较相等性——两者会因设备时区不同而结果不同；
  /// * 请比较 `year/month/day/hour/minute` 组件，或使用 [occurredAtLocal]
  ///   （瞬时语义，按设备时区呈现）；
  /// * 月份归属与账单筛选内部统一使用本字段，保证历史账目不受时区变化影响。
  DateTime get wallClock =>
      occurredAtUtc.add(Duration(minutes: utcOffsetMinutes));

  /// 与 [wallClock] 同一墙上时间，但按设备本地时区重新映射（仅用于展示）。
  DateTime get wallClockLocal => wallClock.toLocal();

  /// 所属月键。
  MonthKey get monthKey => MonthKey.of(wallClock);

  /// 是否已删除。
  bool get isDeleted => deletedAtUtc != null;

  /// 转账手续费与金额之和。
  int get totalCents =>
      kind == TxKind.transfer ? amountCents + feeCents : amountCents;

  /// 校验全部不变量，返回首个错误；全部通过时返回 null。
  LedgerError? validate() {
    if (!Money.isValidAmount(amountCents)) {
      return InvalidAmountError(amountCents);
    }
    if (feeCents < 0) {
      return const InvalidAmountError(0);
    }
    switch (kind) {
      case TxKind.expense:
      case TxKind.income:
        if (toAccountId != null) {
          return const InvalidTransferError('非转账交易不能指定转入账户');
        }
        final String? category = categoryId;
        if (category == null) {
          return MissingCategoryError(kind);
        }
      case TxKind.transfer:
        final String? to = toAccountId;
        if (to == null) {
          return const InvalidTransferError('转账必须选择转入账户');
        }
        if (to == accountId) {
          return const SameAccountTransferError();
        }
    }
    if (splits.isNotEmpty) {
      final int sum =
          splits.fold(0, (int acc, TxSplit s) => acc + s.amountCents);
      if (sum != amountCents) {
        return const InvalidTransferError('分项金额之和必须等于交易金额');
      }
      for (final TxSplit split in splits) {
        if (split.amountCents <= 0) {
          return const InvalidTransferError('分项金额必须大于 0');
        }
      }
    }
    return null;
  }

  /// 复制并覆盖部分字段；`clearXxx` 为 true 时清空可空字段。
  Transaction copyWith({
    String? id,
    TxKind? kind,
    int? amountCents,
    String? accountId,
    String? toAccountId,
    int? feeCents,
    String? categoryId,
    DateTime? occurredAtUtc,
    int? utcOffsetMinutes,
    String? note,
    String? payee,
    String? tag,
    List<TxSplit>? splits,
    DateTime? createdAtUtc,
    DateTime? updatedAtUtc,
    DateTime? deletedAtUtc,
    bool clearToAccountId = false,
    bool clearCategoryId = false,
    bool clearNote = false,
    bool clearPayee = false,
    bool clearDeletedAt = false,
  }) {
    return Transaction(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      amountCents: amountCents ?? this.amountCents,
      accountId: accountId ?? this.accountId,
      toAccountId: clearToAccountId ? null : (toAccountId ?? this.toAccountId),
      feeCents: feeCents ?? this.feeCents,
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      occurredAtUtc: occurredAtUtc ?? this.occurredAtUtc,
      utcOffsetMinutes: utcOffsetMinutes ?? this.utcOffsetMinutes,
      note: clearNote ? null : (note ?? this.note),
      payee: clearPayee ? null : (payee ?? this.payee),
      tag: tag ?? this.tag,
      splits: splits ?? this.splits,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      deletedAtUtc: clearDeletedAt ? null : (deletedAtUtc ?? this.deletedAtUtc),
    );
  }

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'kind': kind.name,
        'amountCents': amountCents,
        'accountId': accountId,
        'toAccountId': toAccountId,
        'feeCents': feeCents,
        'categoryId': categoryId,
        'occurredAtUtc': occurredAtUtc.toUtc().toIso8601String(),
        'utcOffsetMinutes': utcOffsetMinutes,
        'note': note,
        'payee': payee,
        'tag': tag,
        'splits': splits.map((TxSplit s) => s.toJson()).toList(),
        'createdAtUtc': createdAtUtc?.toUtc().toIso8601String(),
        'updatedAtUtc': updatedAtUtc?.toUtc().toIso8601String(),
        'deletedAtUtc': deletedAtUtc?.toUtc().toIso8601String(),
      };

  @override
  String toString() =>
      'Transaction($id, ${kind.name}, $amountCents, $accountId)';
}
