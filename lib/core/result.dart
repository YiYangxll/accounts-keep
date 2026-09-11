/// 统一失败类型：领域与数据层不抛裸异常，一律返回 [Result]。
library;

import '../domain/ledger_error.dart';

/// 无返回值操作的成功标记（等价于 Rust 的 `()`）。
final class Unit {
  /// 构造。
  const Unit();

  @override
  String toString() => 'Unit';
}

/// 操作结果。`ok` 为 true 时 [value] 有值，否则 [error] 有值。
final class Result<T> {
  const Result._(this._value, this._error);

  /// 成功结果。
  const Result.ok(T value) : this._(value, null);

  /// 失败结果。
  const Result.err(LedgerError error) : this._(null, error);

  final T? _value;
  final LedgerError? _error;

  /// 是否成功。
  bool get isOk => _error == null;

  /// 是否失败。
  bool get isErr => _error != null;

  /// 成功值；失败时抛出 [StateError]。
  T get value {
    final LedgerError? error = _error;
    if (error != null) {
      throw StateError('Result 处于失败态，无法读取 value：$error');
    }
    return _value as T;
  }

  /// 失败原因；成功时为 null。
  LedgerError? get error => _error;

  /// 成功值或给定的回退值。
  T getOrElse(T fallback) => isOk ? _value as T : fallback;

  /// 映射成功值。
  Result<R> map<R>(R Function(T value) transform) {
    if (isOk) {
      return Result<R>.ok(transform(_value as T));
    }
    return Result<R>.err(_error!);
  }

  /// 同时可能失败的映射。
  Result<R> flatMap<R>(Result<R> Function(T value) transform) {
    if (isOk) {
      return transform(_value as T);
    }
    return Result<R>.err(_error!);
  }

  @override
  String toString() =>
      isOk ? 'Result.ok(${_value.toString()})' : 'Result.err($_error)';
}
