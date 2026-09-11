/// 领域模型补充测试：覆盖 copyWith 全字段、枚举标签、序列化边界与构造分支。
library;

import 'package:accounts_keep_test/domain/account.dart';
import 'package:accounts_keep_test/domain/category.dart';
import 'package:accounts_keep_test/domain/enums.dart';
import 'package:accounts_keep_test/domain/ledger_error.dart';
import 'package:accounts_keep_test/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

void main() {
  group('枚举映射完整性', () {
    test('TxKind 标签与符号', () {
      expect(TxKind.expense.label, '支出');
      expect(TxKind.income.label, '收入');
      expect(TxKind.transfer.label, '转账');
      expect(TxKind.income.sign, 1);
      expect(TxKind.expense.sign, -1);
      expect(TxKind.transfer.sign, -1);
      for (final TxKind kind in TxKind.values) {
        expect(TxKindLabel.tryParse(kind.storageName), kind);
      }
      expect(TxKindLabel.tryParse(null), isNull);
      expect(TxKindLabel.tryParse('Expense'), isNull);
    });

    test('AccountKind 标签与负债判定', () {
      expect(AccountKind.cash.label, '现金');
      expect(AccountKind.debitCard.label, '储蓄卡');
      expect(AccountKind.alipay.label, '支付宝');
      expect(AccountKind.wechat.label, '微信');
      expect(AccountKind.creditCard.label, '信用卡');
      expect(AccountKind.other.label, '其他');
      expect(AccountKind.creditCard.isLiability, isTrue);
      expect(AccountKind.cash.isLiability, isFalse);
      for (final AccountKind kind in AccountKind.values) {
        expect(AccountKindLabel.tryParse(kind.name), kind);
      }
      expect(AccountKindLabel.tryParse('credit_card'), isNull);
    });

    test('CategoryKind 标签与互转', () {
      expect(CategoryKind.expense.label, '支出');
      expect(CategoryKind.income.label, '收入');
      expect(CategoryKind.expense.asTxKind, TxKind.expense);
      expect(CategoryKind.income.asTxKind, TxKind.income);
      for (final CategoryKind kind in CategoryKind.values) {
        expect(CategoryKindLabel.tryParse(kind.name), kind);
      }
      expect(CategoryKindLabel.tryParse(''), isNull);
    });
  });

  group('Transaction.copyWith', () {
    final Transaction base = expense(
      id: 't1',
      amountCents: 1000,
      accountId: 'acc_a',
      categoryId: 'cat_a',
      occurredAt: DateTime(2026, 3, 10, 12),
      note: '备注',
      payee: '商户',
    );

    test('逐字段覆盖', () {
      final Transaction updated = base.copyWith(
        id: 't2',
        kind: TxKind.income,
        amountCents: 2000,
        accountId: 'acc_b',
        categoryId: 'cat_b',
        occurredAtUtc: DateTime.utc(2026, 4, 1),
        utcOffsetMinutes: 60,
        note: '新备注',
        payee: '新商户',
        tag: '标签',
        updatedAtUtc: DateTime.utc(2026, 4, 2),
        createdAtUtc: DateTime.utc(2026, 4, 2),
      );
      expect(updated.id, 't2');
      expect(updated.kind, TxKind.income);
      expect(updated.amountCents, 2000);
      expect(updated.accountId, 'acc_b');
      expect(updated.categoryId, 'cat_b');
      expect(updated.utcOffsetMinutes, 60);
      expect(updated.note, '新备注');
      expect(updated.payee, '新商户');
      expect(updated.tag, '标签');
      expect(updated.createdAtUtc, DateTime.utc(2026, 4, 2));
      expect(updated.updatedAtUtc, DateTime.utc(2026, 4, 2));
    });

    test('清空可空字段', () {
      final Transaction transferTx = transfer(
        id: 't3',
        amountCents: 500,
        fromAccountId: 'acc_a',
        toAccountId: 'acc_b',
      ).copyWith(deletedAtUtc: DateTime.utc(2026, 3, 11));
      final Transaction cleared = transferTx.copyWith(
        clearToAccountId: true,
        clearCategoryId: true,
        clearNote: true,
        clearPayee: true,
        clearDeletedAt: true,
      );
      expect(cleared.toAccountId, isNull);
      expect(cleared.categoryId, isNull);
      expect(cleared.note, isNull);
      expect(cleared.payee, isNull);
      expect(cleared.isDeleted, isFalse);
    });

    test('转账与分类的互斥由 validate 兜底', () {
      final Transaction bad = base.copyWith(
        kind: TxKind.transfer,
        categoryId: 'cat_a',
      );
      expect(bad.validate(), isA<InvalidTransferError>());
    });

    test('分项金额必须为正', () {
      final Transaction tx = base.copyWith(
        splits: const <TxSplit>[
          TxSplit(categoryId: 'c1', amountCents: 1000),
          TxSplit(categoryId: 'c2', amountCents: 0),
        ],
      );
      expect(tx.validate(), isA<InvalidTransferError>());
    });

    test('手续费为负被拒绝', () {
      expect(
        base.copyWith(feeCents: -5).validate(),
        isA<InvalidAmountError>(),
      );
    });

    test('totalCents 对非转账等于金额', () {
      expect(base.totalCents, 1000);
    });

    test('TxSplit 往返与相等性', () {
      const TxSplit split = TxSplit(
        categoryId: 'c1',
        amountCents: 300,
        note: '分项',
      );
      expect(TxSplit.fromJson(split.toJson()), split);
      expect(split.hashCode, TxSplit.fromJson(split.toJson()).hashCode);
      expect(
        const TxSplit(categoryId: 'c1', amountCents: 300, note: '分项'),
        split,
      );
    });
  });

  group('Account.copyWith', () {
    final Account base = account(
      id: 'a1',
      name: '现金',
      kind: AccountKind.cash,
      initialBalanceCents: 100,
    );

    test('逐字段覆盖', () {
      final Account updated = base.copyWith(
        id: 'a2',
        name: '零钱',
        kind: AccountKind.wechat,
        initialBalanceCents: -500,
        iconName: 'wechat',
        colorHex: '#07C160',
        sortOrder: 9,
      );
      expect(updated.id, 'a2');
      expect(updated.name, '零钱');
      expect(updated.kind, AccountKind.wechat);
      expect(updated.initialBalanceCents, -500);
      expect(updated.iconName, 'wechat');
      expect(updated.colorHex, '#07C160');
      expect(updated.sortOrder, 9);
    });

    test('相等性包含全部字段', () {
      expect(base, base.copyWith());
      expect(base == base.copyWith(name: '别的'), isFalse);
      expect(base.hashCode, base.copyWith().hashCode);
    });
  });

  group('Category.copyWith', () {
    final Category base = category(id: 'c1', name: '餐饮');

    test('逐字段覆盖与清空父子关系', () {
      final Category sub = base.copyWith(
        id: 'c2',
        name: '早餐',
        parentId: 'c1',
        iconName: 'restaurant',
        colorHex: '#FF7043',
        sortOrder: 3,
      );
      expect(sub.isSubCategory, isTrue);
      expect(sub.iconName, 'restaurant');
      expect(sub.sortOrder, 3);

      final Category cleared = sub.copyWith(clearParentId: true);
      expect(cleared.parentId, isNull);
      expect(cleared.isSubCategory, isFalse);

      final Category archived =
          base.copyWith(archivedAt: DateTime.utc(2026, 3, 1));
      expect(archived.isArchived, isTrue);
      expect(archived.copyWith(clearArchivedAt: true).isArchived, isFalse);
    });

    test('相等性', () {
      expect(base, base.copyWith());
      expect(base == base.copyWith(name: '别的'), isFalse);
      expect(base.hashCode, base.copyWith().hashCode);
    });
  });

  group('LedgerError 文案', () {
    test('每个错误都携带可展示的中文提示', () {
      const List<LedgerError> errors = <LedgerError>[
        InvalidAmountError(0),
        UnparsableAmountError('abc'),
        InvalidTransferError('自定义'),
        SameAccountTransferError(),
        AccountNotFoundError('a'),
        CategoryNotFoundError('c'),
        CategoryKindMismatchError(CategoryKind.income, TxKind.expense),
        MissingCategoryError(TxKind.expense),
        DuplicateNameError('现金'),
        EmptyNameError(),
        AccountInUseError('a', 3),
        CategoryInUseError('c', 2),
        StorageError('磁盘错误'),
        CorruptDataError('文件损坏'),
        UnsupportedSchemaError(9, 1),
        MalformedImportError('缺少字段'),
        UnknownEnumValueError('kind', 'x'),
        NotFoundError('不存在'),
      ];
      for (final LedgerError error in errors) {
        expect(error.message, isNotEmpty);
        expect(error.toString(), contains(error.message));
      }
      expect(const AccountInUseError('a', 3).message, contains('3'));
      expect(const CategoryInUseError('c', 2).message, contains('2'));
      expect(
        const UnsupportedSchemaError(9, 1).message,
        allOf(contains('9'), contains('1')),
      );
      expect(const UnknownEnumValueError('kind', 'x').field, 'kind');
    });
  });
}
