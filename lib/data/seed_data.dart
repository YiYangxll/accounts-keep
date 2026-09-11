/// 首次启动的默认账户与分类。
///
/// 只写入账户与分类这类「元数据」，不注入任何假流水，避免用户误以为是自己的数据。
library;

import '../domain/account.dart';
import '../domain/category.dart';
import '../domain/enums.dart';

/// 默认账户 id（稳定常量，便于测试与迁移引用）。
abstract final class SeedAccountIds {
  /// 现金。
  static const String cash = 'acc_cash';

  /// 储蓄卡。
  static const String debitCard = 'acc_debit';

  /// 支付宝。
  static const String alipay = 'acc_alipay';

  /// 微信零钱。
  static const String wechat = 'acc_wechat';

  /// 信用卡。
  static const String creditCard = 'acc_credit';
}

/// 默认分类 id。
abstract final class SeedCategoryIds {
  /// 餐饮。
  static const String food = 'cat_food';

  /// 交通。
  static const String transport = 'cat_transport';

  /// 购物。
  static const String shopping = 'cat_shopping';

  /// 居住。
  static const String housing = 'cat_housing';

  /// 通讯。
  static const String communication = 'cat_communication';

  /// 娱乐。
  static const String entertainment = 'cat_entertainment';

  /// 医疗。
  static const String medical = 'cat_medical';

  /// 学习。
  static const String education = 'cat_education';

  /// 人情往来。
  static const String social = 'cat_social';

  /// 其他支出。
  static const String otherExpense = 'cat_other_expense';

  /// 工资。
  static const String salary = 'cat_salary';

  /// 奖金。
  static const String bonus = 'cat_bonus';

  /// 兼职。
  static const String partTime = 'cat_part_time';

  /// 投资收益。
  static const String investment = 'cat_investment';

  /// 红包。
  static const String redPacket = 'cat_red_packet';

  /// 其他收入。
  static const String otherIncome = 'cat_other_income';
}

/// 生成默认账户列表。
List<Account> seedAccounts() => const <Account>[
      Account(
        id: SeedAccountIds.cash,
        name: '现金',
        kind: AccountKind.cash,
        iconName: 'cash',
        colorHex: '#FF9800',
        sortOrder: 0,
      ),
      Account(
        id: SeedAccountIds.debitCard,
        name: '储蓄卡',
        kind: AccountKind.debitCard,
        iconName: 'bank',
        colorHex: '#2196F3',
        sortOrder: 1,
      ),
      Account(
        id: SeedAccountIds.alipay,
        name: '支付宝',
        kind: AccountKind.alipay,
        iconName: 'alipay',
        colorHex: '#1677FF',
        sortOrder: 2,
      ),
      Account(
        id: SeedAccountIds.wechat,
        name: '微信零钱',
        kind: AccountKind.wechat,
        iconName: 'wechat',
        colorHex: '#07C160',
        sortOrder: 3,
      ),
      Account(
        id: SeedAccountIds.creditCard,
        name: '信用卡',
        kind: AccountKind.creditCard,
        iconName: 'credit_card',
        colorHex: '#E53935',
        sortOrder: 4,
      ),
    ];

/// 生成默认分类列表。
List<Category> seedCategories() => const <Category>[
      Category(
        id: SeedCategoryIds.food,
        name: '餐饮',
        kind: CategoryKind.expense,
        iconName: 'restaurant',
        colorHex: '#FF7043',
        sortOrder: 0,
      ),
      Category(
        id: SeedCategoryIds.transport,
        name: '交通',
        kind: CategoryKind.expense,
        iconName: 'transport',
        colorHex: '#42A5F5',
        sortOrder: 1,
      ),
      Category(
        id: SeedCategoryIds.shopping,
        name: '购物',
        kind: CategoryKind.expense,
        iconName: 'shopping',
        colorHex: '#AB47BC',
        sortOrder: 2,
      ),
      Category(
        id: SeedCategoryIds.housing,
        name: '居住',
        kind: CategoryKind.expense,
        iconName: 'home',
        colorHex: '#8D6E63',
        sortOrder: 3,
      ),
      Category(
        id: SeedCategoryIds.communication,
        name: '通讯',
        kind: CategoryKind.expense,
        iconName: 'phone',
        colorHex: '#26A69A',
        sortOrder: 4,
      ),
      Category(
        id: SeedCategoryIds.entertainment,
        name: '娱乐',
        kind: CategoryKind.expense,
        iconName: 'game',
        colorHex: '#EC407A',
        sortOrder: 5,
      ),
      Category(
        id: SeedCategoryIds.medical,
        name: '医疗',
        kind: CategoryKind.expense,
        iconName: 'medical',
        colorHex: '#EF5350',
        sortOrder: 6,
      ),
      Category(
        id: SeedCategoryIds.education,
        name: '学习',
        kind: CategoryKind.expense,
        iconName: 'book',
        colorHex: '#5C6BC0',
        sortOrder: 7,
      ),
      Category(
        id: SeedCategoryIds.social,
        name: '人情往来',
        kind: CategoryKind.expense,
        iconName: 'gift',
        colorHex: '#FFA726',
        sortOrder: 8,
      ),
      Category(
        id: SeedCategoryIds.otherExpense,
        name: '其他',
        kind: CategoryKind.expense,
        iconName: 'more',
        colorHex: '#90A4AE',
        sortOrder: 9,
      ),
      Category(
        id: SeedCategoryIds.salary,
        name: '工资',
        kind: CategoryKind.income,
        iconName: 'salary',
        colorHex: '#66BB6A',
        sortOrder: 0,
      ),
      Category(
        id: SeedCategoryIds.bonus,
        name: '奖金',
        kind: CategoryKind.income,
        iconName: 'bonus',
        colorHex: '#26C6DA',
        sortOrder: 1,
      ),
      Category(
        id: SeedCategoryIds.partTime,
        name: '兼职',
        kind: CategoryKind.income,
        iconName: 'work',
        colorHex: '#9CCC65',
        sortOrder: 2,
      ),
      Category(
        id: SeedCategoryIds.investment,
        name: '投资收益',
        kind: CategoryKind.income,
        iconName: 'trending_up',
        colorHex: '#FFCA28',
        sortOrder: 3,
      ),
      Category(
        id: SeedCategoryIds.redPacket,
        name: '红包',
        kind: CategoryKind.income,
        iconName: 'red_packet',
        colorHex: '#EF5350',
        sortOrder: 4,
      ),
      Category(
        id: SeedCategoryIds.otherIncome,
        name: '其他',
        kind: CategoryKind.income,
        iconName: 'more',
        colorHex: '#90A4AE',
        sortOrder: 5,
      ),
    ];
