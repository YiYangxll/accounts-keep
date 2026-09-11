/// 收支分类模型（支持一级分类与可选二级分类）。
library;

import '../core/json_x.dart';
import 'enums.dart';
import 'ledger_error.dart';

/// 一个收支分类。
final class Category {
  /// 构造。
  const Category({
    required this.id,
    required this.name,
    required this.kind,
    this.parentId,
    this.iconName,
    this.colorHex,
    this.sortOrder = 0,
    this.archivedAt,
  });

  /// 从持久化 JSON 还原。
  factory Category.fromJson(Map<String, Object?> json) {
    final String rawKind = json.requireString('kind');
    final CategoryKind? kind = CategoryKindLabel.tryParse(rawKind);
    if (kind == null) {
      throw UnknownEnumValueError('kind', rawKind);
    }
    return Category(
      id: json.requireString('id'),
      name: json.requireString('name'),
      kind: kind,
      parentId: json.optionalString('parentId'),
      iconName: json.optionalString('iconName'),
      colorHex: json.optionalString('colorHex'),
      sortOrder: json.optionalInt('sortOrder') ?? 0,
      archivedAt: json.optionalDateTime('archivedAt'),
    );
  }

  /// 唯一标识。
  final String id;

  /// 分类名称。
  final String name;

  /// 所属收支类型。
  final CategoryKind kind;

  /// 上级分类 id；为空表示一级分类。
  final String? parentId;

  /// 图标名（UI 层映射）。
  final String? iconName;

  /// 颜色（`#RRGGBB`）。
  final String? colorHex;

  /// 排序权重。
  final int sortOrder;

  /// 归档时间；非空表示已归档，不再出现在选择列表中，但历史流水仍可读。
  final DateTime? archivedAt;

  /// 是否已归档。
  bool get isArchived => archivedAt != null;

  /// 是否二级分类。
  bool get isSubCategory => parentId != null;

  /// 复制并覆盖部分字段。
  Category copyWith({
    String? id,
    String? name,
    CategoryKind? kind,
    String? parentId,
    String? iconName,
    String? colorHex,
    int? sortOrder,
    DateTime? archivedAt,
    bool clearParentId = false,
    bool clearArchivedAt = false,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      parentId: clearParentId ? null : (parentId ?? this.parentId),
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
        'parentId': parentId,
        'iconName': iconName,
        'colorHex': colorHex,
        'sortOrder': sortOrder,
        'archivedAt': archivedAt?.toUtc().toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      other is Category &&
      other.id == id &&
      other.name == name &&
      other.kind == kind &&
      other.parentId == parentId &&
      other.iconName == iconName &&
      other.colorHex == colorHex &&
      other.sortOrder == sortOrder &&
      other.archivedAt == archivedAt;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        kind,
        parentId,
        iconName,
        colorHex,
        sortOrder,
        archivedAt,
      );

  @override
  String toString() => 'Category($id, $name, ${kind.name})';
}
