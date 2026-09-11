/// 领域错误类型：所有可预期的业务失败都用一个密封类表达，
/// 使调用方可以用 `switch` 穷尽处理，并给出中文提示文案。
library;

/// 交易类型（收入/支出/转账）。
enum TxKind { expense, income, transfer }

/// 账户类型。
enum AccountKind { cash, debitCard, alipay, wechat, creditCard, other }

/// 分类所属的收支类型。
enum CategoryKind { expense, income }

/// 账户与分类共用的类型标签。
extension TxKindLabel on TxKind {
  /// 中文名称。
  String get label => switch (this) {
        TxKind.expense => '支出',
        TxKind.income => '收入',
        TxKind.transfer => '转账',
      };

  /// 持久化用的英文名。
  String get storageName => name;

  /// 该类型下余额的增减方向：收入/转入为正。
  int get sign => this == TxKind.income ? 1 : -1;

  /// 从持久化文本还原，未知值返回 null。
  static TxKind? tryParse(String? text) {
    for (final TxKind kind in TxKind.values) {
      if (kind.name == text) {
        return kind;
      }
    }
    return null;
  }
}

/// 账户类型的中文与图标映射（图标名由 UI 层映射，领域层保持无 Flutter 依赖）。
extension AccountKindLabel on AccountKind {
  /// 中文名称。
  String get label => switch (this) {
        AccountKind.cash => '现金',
        AccountKind.debitCard => '储蓄卡',
        AccountKind.alipay => '支付宝',
        AccountKind.wechat => '微信',
        AccountKind.creditCard => '信用卡',
        AccountKind.other => '其他',
      };

  /// 是否属于负债类账户（余额为负表示欠款）。
  bool get isLiability => this == AccountKind.creditCard;

  /// 从持久化文本还原，未知值返回 null。
  static AccountKind? tryParse(String? text) {
    for (final AccountKind kind in AccountKind.values) {
      if (kind.name == text) {
        return kind;
      }
    }
    return null;
  }
}

/// 分类收支类型的中文映射。
extension CategoryKindLabel on CategoryKind {
  /// 中文名称。
  String get label => switch (this) {
        CategoryKind.expense => '支出',
        CategoryKind.income => '收入',
      };

  /// 与交易类型互转；转账没有分类，返回 null。
  TxKind? get asTxKind => switch (this) {
        CategoryKind.expense => TxKind.expense,
        CategoryKind.income => TxKind.income,
      };

  /// 从持久化文本还原，未知值返回 null。
  static CategoryKind? tryParse(String? text) {
    for (final CategoryKind kind in CategoryKind.values) {
      if (kind.name == text) {
        return kind;
      }
    }
    return null;
  }
}
