/// 账户模型。
library;

import '../core/json_x.dart';
import 'enums.dart';
import 'ledger_error.dart';

/// 一个资金账户（现金、储蓄卡、支付宝、微信、信用卡等）。
final class Account {
  /// 构造。
  const Account({
    required this.id,
    required this.name,
    required this.kind,
    this.initialBalanceCents = 0,
    this.iconName,
    this.colorHex,
    this.sortOrder = 0,
    this.archivedAt,
  });

  /// 从持久化 JSON 还原。
  factory Account.fromJson(Map<String, Object?> json) {
    final AccountKind? kind =
        AccountKindLabel.tryParse(json.requireString('kind'));
    if (kind == null) {
      throw UnknownEnumValueError('kind', json.requireString('kind'));
    }
    return Account(
      id: json.requireString('id'),
      name: json.requireString('name'),
      kind: kind,
      initialBalanceCents: json.optionalInt('initialBalanceCents') ?? 0,
      iconName: json.optionalString('iconName'),
      colorHex: json.optionalString('colorHex'),
      sortOrder: json.optionalInt('sortOrder') ?? 0,
      archivedAt: json.optionalDateTime('archivedAt'),
    );
  }

  /// 唯一标识。
  final String id;

  /// 账户名称。
  final String name;

  /// 账户类型。
  final AccountKind kind;

  /// 期初余额（分）。信用卡为负数表示已有欠款。
  final int initialBalanceCents;

  /// 图标名（由 UI 层映射到具体图标）。
  final String? iconName;

  /// 颜色（`#RRGGBB`）。
  final String? colorHex;

  /// 排序权重，越小越靠前。
  final int sortOrder;

  /// 归档时间；非空表示已归档，不再参与默认列表与净资产统计。
  final DateTime? archivedAt;

  /// 是否为负债账户。
  bool get isLiability => kind.isLiability;

  /// 是否已归档。
  bool get isArchived => archivedAt != null;

  /// 复制并覆盖部分字段。
  Account copyWith({
    String? id,
    String? name,
    AccountKind? kind,
    int? initialBalanceCents,
    String? iconName,
    String? colorHex,
    int? sortOrder,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      initialBalanceCents: initialBalanceCents ?? this.initialBalanceCents,
      iconName: iconName ?? this.iconName,
      colorHex: colorHex ?? this.colorHex,
      sortOrder: sortOrder ?? this.sortOrder,
      archivedAt: clearArchivedAt ? null : (archivedAt ?? this.archivedAt),
    );
  }

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'kind': kind.name,
        'initialBalanceCents': initialBalanceCents,
        'iconName': iconName,
        'colorHex': colorHex,
        'sortOrder': sortOrder,
        'archivedAt': archivedAt?.toUtc().toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      other is Account &&
      other.id == id &&
      other.name == name &&
      other.kind == kind &&
      other.initialBalanceCents == initialBalanceCents &&
      other.iconName == iconName &&
      other.colorHex == colorHex &&
      other.sortOrder == sortOrder &&
      other.archivedAt == archivedAt;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        kind,
        initialBalanceCents,
        iconName,
        colorHex,
        sortOrder,
        archivedAt,
      );

  @override
  String toString() => 'Account($id, $name, ${kind.name})';
}
