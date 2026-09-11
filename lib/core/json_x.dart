/// JSON 解析辅助：对持久化数据做防御式解析，缺失或类型不符时抛出
/// [CorruptDataError]，避免把坏数据静默读成默认值。
library;

import '../domain/ledger_error.dart';

/// 在 Map 上安全读取字段的扩展。
extension JsonX on Map<String, Object?> {
  /// 读取必填字符串。
  String requireString(String key) {
    final Object? value = this[key];
    if (value is String) {
      return value;
    }
    throw CorruptDataError('字段 $key 缺失或不是字符串：$value');
  }

  /// 读取可选字符串，空字符串视为 null。
  String? optionalString(String key) {
    final Object? value = this[key];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw CorruptDataError('字段 $key 不是字符串：$value');
    }
    return value.isEmpty ? null : value;
  }

  /// 读取必填整数。
  int requireInt(String key) {
    final Object? value = this[key];
    if (value is int) {
      return value;
    }
    if (value is double && value == value.roundToDouble()) {
      return value.toInt();
    }
    throw CorruptDataError('字段 $key 缺失或不是整数：$value');
  }

  /// 读取可选整数。
  int? optionalInt(String key) {
    final Object? value = this[key];
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is double && value == value.roundToDouble()) {
      return value.toInt();
    }
    throw CorruptDataError('字段 $key 不是整数：$value');
  }

  /// 读取必填布尔值。
  bool requireBool(String key) {
    final Object? value = this[key];
    if (value is bool) {
      return value;
    }
    throw CorruptDataError('字段 $key 缺失或不是布尔值：$value');
  }

  /// 读取必填的 Map。
  Map<String, Object?> requireMap(String key) {
    final Object? value = this[key];
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map<Object?, Object?>) {
      return value
          .map((Object? k, Object? v) => MapEntry<String, Object?>('$k', v));
    }
    throw CorruptDataError('字段 $key 缺失或不是对象：$value');
  }

  /// 读取可选 Map。
  Map<String, Object?>? optionalMap(String key) {
    final Object? value = this[key];
    if (value == null) {
      return null;
    }
    return requireMap(key);
  }

  /// 读取必填的 List。
  List<Object?> requireList(String key) {
    final Object? value = this[key];
    if (value is List<Object?>) {
      return value;
    }
    throw CorruptDataError('字段 $key 缺失或不是数组：$value');
  }

  /// 读取可选 List。
  List<Object?> optionalList(String key) {
    final Object? value = this[key];
    if (value == null) {
      return const <Object?>[];
    }
    if (value is List<Object?>) {
      return value;
    }
    throw CorruptDataError('字段 $key 不是数组：$value');
  }

  /// 读取可选日期（ISO 8601 瞬时）；字段缺失或为空字符串时返回 null。
  ///
  /// 字段存在但无法解析时抛出 [CorruptDataError]：日历类字段一旦静默变成 null，
  /// 会连带影响月份归属与账期统计，宁可报错也不要让坏数据静默通过。
  DateTime? optionalDateTime(String key) {
    final String? text = optionalString(key);
    if (text == null) {
      return null;
    }
    final DateTime? parsed = DateTime.tryParse(text);
    if (parsed == null) {
      throw CorruptDataError('字段 $key 不是合法时间：$text');
    }
    return parsed.toUtc();
  }

  /// 读取必填日期（ISO 8601 瞬时）。
  DateTime requireDateTime(String key) {
    final DateTime? value = optionalDateTime(key);
    if (value == null) {
      throw CorruptDataError('字段 $key 缺失或不是合法时间：${this[key]}');
    }
    return value;
  }
}

/// 把 List 中的每项转成 Map 后交给 [parse]。
List<T> parseObjectList<T>(
  List<Object?> raw,
  T Function(Map<String, Object?> json) parse,
) {
  final List<T> result = <T>[];
  for (final Object? item in raw) {
    if (item is! Map<Object?, Object?>) {
      throw CorruptDataError('数组元素不是对象：$item');
    }
    final Map<String, Object?> json =
        item.map((Object? k, Object? v) => MapEntry<String, Object?>('$k', v));
    result.add(parse(json));
  }
  return result;
}
