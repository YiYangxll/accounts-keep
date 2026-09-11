/// 领域层可预期的失败类型。
library;

import 'enums.dart';

/// 所有领域错误的基类，携带可直接展示给用户的中文 [message]。
sealed class LedgerError {
  const LedgerError(this.message);

  /// 面向用户的中文提示。
  final String message;

  @override
  String toString() => '$runtimeType($message)';
}

/// 金额非法（为零、负数或超出上限）。
final class InvalidAmountError extends LedgerError {
  /// 构造。
  const InvalidAmountError(this.cents) : super('金额必须大于 0，且不超过 1 亿元');

  /// 违规的金额（分）。
  final int cents;
}

/// 金额文本无法解析。
final class UnparsableAmountError extends LedgerError {
  /// 构造。
  const UnparsableAmountError(this.raw) : super('无法识别的金额，请输入形如 12.30 的数字');

  /// 原始输入。
  final String raw;
}

/// 转账的转出与转入账户缺失或不合法。
final class InvalidTransferError extends LedgerError {
  /// 构造。
  const InvalidTransferError(super.message);
}

/// 转账的转出与转入账户相同。
final class SameAccountTransferError extends LedgerError {
  /// 构造。
  const SameAccountTransferError() : super('转出与转入账户不能是同一个账户');
}

/// 引用的账户不存在或已被删除。
final class AccountNotFoundError extends LedgerError {
  /// 构造。
  const AccountNotFoundError(this.accountId) : super('所选账户不存在或已被删除');

  /// 账户 id。
  final String accountId;
}

/// 引用的分类不存在或已被删除。
final class CategoryNotFoundError extends LedgerError {
  /// 构造。
  const CategoryNotFoundError(this.categoryId) : super('所选分类不存在或已被删除');

  /// 分类 id。
  final String categoryId;
}

/// 分类的收支类型与交易类型不匹配。
final class CategoryKindMismatchError extends LedgerError {
  /// 构造。
  const CategoryKindMismatchError(this.categoryKind, this.txKind)
      : super('所选分类与当前记账类型不匹配');

  /// 分类所属类型。
  final CategoryKind categoryKind;

  /// 交易类型。
  final TxKind txKind;
}

/// 缺少必填的分类。
final class MissingCategoryError extends LedgerError {
  /// 构造。
  const MissingCategoryError(this.txKind) : super('请选择分类');

  /// 交易类型。
  final TxKind txKind;
}

/// 名称重复。
final class DuplicateNameError extends LedgerError {
  /// 构造。
  const DuplicateNameError(this.name) : super('已存在同名项，请换一个名称');

  /// 冲突的名称。
  final String name;
}

/// 名称为空。
final class EmptyNameError extends LedgerError {
  /// 构造。
  const EmptyNameError() : super('名称不能为空');
}

/// 账户仍有流水，不能直接物理删除。
final class AccountInUseError extends LedgerError {
  /// 构造。
  const AccountInUseError(this.accountId, this.recordCount)
      : super('该账户下还有 $recordCount 条流水，请先选择处理方式');

  /// 账户 id。
  final String accountId;

  /// 关联流水条数。
  final int recordCount;
}

/// 分类仍被流水引用，只能归档。
final class CategoryInUseError extends LedgerError {
  /// 构造。
  const CategoryInUseError(this.categoryId, this.recordCount)
      : super('该分类已被 $recordCount 条流水使用，只能归档不能删除');

  /// 分类 id。
  final String categoryId;

  /// 引用条数。
  final int recordCount;
}

/// 存储读写失败。
final class StorageError extends LedgerError {
  /// 构造。
  const StorageError(super.message, {this.cause});

  /// 底层原因，便于排查。
  final Object? cause;
}

/// 数据文件损坏或格式无法识别。
final class CorruptDataError extends LedgerError {
  /// 构造。
  const CorruptDataError(super.message, {this.cause});

  /// 底层原因。
  final Object? cause;
}

/// 导入文件的数据版本不受支持。
final class UnsupportedSchemaError extends LedgerError {
  /// 构造。
  const UnsupportedSchemaError(this.found, this.supported)
      : super('数据版本 $found 不受支持（当前支持 $supported）');

  /// 文件中发现的版本。
  final int found;

  /// 当前支持的版本。
  final int supported;
}

/// 导入文件缺少必要字段。
final class MalformedImportError extends LedgerError {
  /// 构造。
  const MalformedImportError(super.message);
}

/// 数据文件中出现无法识别的枚举值。
final class UnknownEnumValueError extends LedgerError {
  /// 构造。
  const UnknownEnumValueError(this.field, this.rawValue)
      : super('字段 $field 的取值 "$rawValue" 无法识别，数据可能来自更高版本');

  /// 出错的字段名。
  final String field;

  /// 原始取值。
  final String rawValue;
}

/// 交易或记录不存在。
final class NotFoundError extends LedgerError {
  /// 构造。
  const NotFoundError(super.message);
}
