/// 领域模型测试：不变量校验、序列化与日期归属。
library;

import 'package:accounts_keep_test/core/date_x.dart';
import 'package:accounts_keep_test/domain/account.dart';
import 'package:accounts_keep_test/domain/category.dart';
import 'package:accounts_keep_test/domain/enums.dart';
import 'package:accounts_keep_test/domain/ledger_error.dart';
import 'package:accounts_keep_test/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

void main() {
  group('Transaction 不变量', () {
    test('合法的支出', () {
      final Transaction tx = expense(
        id: 't1',
        amountCents: 1000,
        accountId: 'acc',
        categoryId: 'cat',
      );
      expect(tx.validate(), isNull);
      expect(tx.monthKey, const MonthKey(2026, 3));
    });

    test('金额必须大于 0', () {
      final Transaction zero = expense(
        id: 't1',
        amountCents: 0,
        accountId: 'acc',
        categoryId: 'cat',
      );
      expect(zero.validate(), isA<InvalidAmountError>());

      final Transaction negative = expense(
        id: 't2',
        amountCents: -100,
        accountId: 'acc',
        categoryId: 'cat',
      );
      expect(negative.validate(), isA<InvalidAmountError>());
    });

    test('金额不能超过上限', () {
      final Transaction huge = expense(
        id: 't1',
        amountCents: 100000001 * 100,
        accountId: 'acc',
        categoryId: 'cat',
      );
      expect(huge.validate(), isA<InvalidAmountError>());
    });

    test('支出必须有分类', () {
      final Transaction tx = Transaction(
        id: 't1',
        kind: TxKind.expense,
        amountCents: 100,
        accountId: 'acc',
        occurredAtUtc: DateTime.utc(2026, 3, 1),
        utcOffsetMinutes: 0,
      );
      expect(tx.validate(), isA<MissingCategoryError>());
    });

    test('非转账不能有转入账户', () {
      final Transaction tx = Transaction(
        id: 't1',
        kind: TxKind.income,
        amountCents: 100,
        accountId: 'acc',
        toAccountId: 'acc2',
        categoryId: 'cat',
        occurredAtUtc: DateTime.utc(2026, 3, 1),
        utcOffsetMinutes: 0,
      );
      expect(tx.validate(), isA<InvalidTransferError>());
    });

    test('转账必须指定转入账户', () {
      final Transaction tx = Transaction(
        id: 't1',
        kind: TxKind.transfer,
        amountCents: 100,
        accountId: 'acc',
        occurredAtUtc: DateTime.utc(2026, 3, 1),
        utcOffsetMinutes: 0,
      );
      expect(tx.validate(), isA<InvalidTransferError>());
    });

    test('不能转给自己', () {
      final Transaction tx = transfer(
        id: 't1',
        amountCents: 100,
        fromAccountId: 'acc',
        toAccountId: 'acc',
      );
      expect(tx.validate(), isA<SameAccountTransferError>());
    });

    test('手续费不能为负', () {
      final Transaction tx = transfer(
        id: 't1',
        amountCents: 100,
        fromAccountId: 'a1',
        toAccountId: 'a2',
        feeCents: -1,
      );
      expect(tx.validate(), isA<InvalidAmountError>());
    });

    test('分项之和必须等于总额', () {
      final Transaction tx = expense(
        id: 't1',
        amountCents: 100,
        accountId: 'a1',
        categoryId: 'cat',
      ).copyWith(
        splits: const <TxSplit>[
          TxSplit(categoryId: 'c1', amountCents: 60),
          TxSplit(categoryId: 'c2', amountCents: 30),
        ],
      );
      expect(tx.validate(), isA<InvalidTransferError>());

      final Transaction ok = tx.copyWith(
        splits: const <TxSplit>[
          TxSplit(categoryId: 'c1', amountCents: 60),
          TxSplit(categoryId: 'c2', amountCents: 40),
        ],
      );
      expect(ok.validate(), isNull);
    });

    test('转账总额包含手续费', () {
      final Transaction tx = transfer(
        id: 't1',
        amountCents: 1000,
        fromAccountId: 'a1',
        toAccountId: 'a2',
        feeCents: 50,
      );
      expect(tx.totalCents, 1050);
    });
  });

  group('Transaction 序列化', () {
    test('往返一致', () {
      final Transaction original = expense(
        id: 'tx_1',
        amountCents: 12345,
        accountId: 'acc_cash',
        categoryId: 'cat_food',
        occurredAt: DateTime(2026, 3, 8, 14, 5),
        note: '午饭',
        payee: '公司食堂',
      );
      final Transaction restored = Transaction.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.kind, original.kind);
      expect(restored.amountCents, original.amountCents);
      expect(restored.accountId, original.accountId);
      expect(restored.categoryId, original.categoryId);
      expect(restored.note, original.note);
      expect(restored.payee, original.payee);
      expect(restored.occurredAtUtc, original.occurredAtUtc);
      expect(restored.utcOffsetMinutes, original.utcOffsetMinutes);
      expect(restored.wallClock, original.wallClock);
    });

    test('转账往返一致', () {
      final Transaction original = transfer(
        id: 'tx_2',
        amountCents: 5000,
        fromAccountId: 'a1',
        toAccountId: 'a2',
        feeCents: 100,
      );
      final Transaction restored = Transaction.fromJson(original.toJson());
      expect(restored.toAccountId, 'a2');
      expect(restored.feeCents, 100);
      expect(restored.categoryId, isNull);
    });

    test('未知类型会报错而不是静默降级', () {
      final Map<String, Object?> broken = expense(
        id: 'tx_3',
        amountCents: 100,
        accountId: 'a',
        categoryId: 'c',
      ).toJson();
      broken['kind'] = 'unknown';
      expect(
        () => Transaction.fromJson(broken),
        throwsA(isA<UnknownEnumValueError>()),
      );
    });

    test('缺少必填字段会报错', () {
      final Map<String, Object?> broken = expense(
        id: 'tx_4',
        amountCents: 100,
        accountId: 'a',
        categoryId: 'c',
      ).toJson();
      broken.remove('amountCents');
      expect(() => Transaction.fromJson(broken), throwsA(isA<LedgerError>()));
    });
  });

  group('日期归属与时区', () {
    test('月键基于记账时的本地时间，而非当前设备时区', () {
      // 记于 UTC+8 的 3 月 1 日 00:30，若按 UTC 归属会错到 2 月。
      final Transaction tx = Transaction(
        id: 't',
        kind: TxKind.expense,
        amountCents: 100,
        accountId: 'a',
        categoryId: 'c',
        occurredAtUtc: DateTime.utc(2026, 2, 28, 16, 30),
        utcOffsetMinutes: 480,
      );
      expect(tx.monthKey, const MonthKey(2026, 3));
      expect(tx.wallClock.day, 1);
      expect(tx.wallClock.hour, 0);
    });

    test('MonthKey 的边界', () {
      expect(const MonthKey(2026, 3).firstDay, DateTime(2026, 3, 1));
      expect(const MonthKey(2026, 3).lastDay, DateTime(2026, 3, 31));
      expect(const MonthKey(2026, 3).nextMonthFirstDay, DateTime(2026, 4, 1));
      // 闰年二月
      expect(const MonthKey(2024, 2).lastDay, DateTime(2024, 2, 29));
      expect(const MonthKey(2025, 2).lastDay, DateTime(2025, 2, 28));
    });

    test('MonthKey 平移与跨年', () {
      expect(const MonthKey(2026, 1).shift(-1), const MonthKey(2025, 12));
      expect(const MonthKey(2026, 12).shift(1), const MonthKey(2027, 1));
      expect(const MonthKey(2026, 3).shift(-15), const MonthKey(2024, 12));
    });

    test('MonthKey 解析与展示', () {
      expect(MonthKey.tryParse('2026-03'), const MonthKey(2026, 3));
      expect(MonthKey.tryParse('2026-13'), isNull);
      expect(MonthKey.tryParse('2026-3'), isNull);
      expect(MonthKey.tryParse('abc'), isNull);
      expect(const MonthKey(2026, 3).toString(), '2026-03');
      expect(const MonthKey(2026, 3).label, '2026年3月');
    });

    test('日期比较忽略时间部分', () {
      final DateTime a = DateTime(2026, 3, 8, 1);
      final DateTime b = DateTime(2026, 3, 8, 23, 59);
      expect(a.isSameDay(b), isTrue);
      expect(a.isSameMonth(b), isTrue);
    });

    test('dateText 与 dateTimeText', () {
      final DateTime dt = DateTime(2026, 3, 8, 9, 5);
      expect(dt.dateText, '2026-03-08');
      expect(dt.dateTimeText, '2026-03-08 09:05');
    });
  });

  group('Account 与 Category', () {
    test('账户往返一致并识别负债', () {
      final Account credit = account(
        id: 'acc_credit',
        name: '信用卡',
        kind: AccountKind.creditCard,
        initialBalanceCents: -50000,
      );
      expect(credit.isLiability, isTrue);
      expect(credit.isArchived, isFalse);
      expect(Account.fromJson(credit.toJson()), credit);
    });

    test('归档标记', () {
      final Account archived = account(id: 'a', name: 'A')
          .copyWith(archivedAt: DateTime.utc(2026, 3, 1));
      expect(archived.isArchived, isTrue);
      expect(archived.copyWith(clearArchivedAt: true).isArchived, isFalse);
    });

    test('分类往返一致并识别二级分类', () {
      const Category sub = Category(
        id: 'c2',
        name: '早餐',
        kind: CategoryKind.expense,
        parentId: 'c1',
      );
      expect(sub.isSubCategory, isTrue);
      expect(Category.fromJson(sub.toJson()), sub);
      expect(CategoryKindLabel.tryParse('income'), CategoryKind.income);
      expect(CategoryKindLabel.tryParse('nope'), isNull);
    });
  });
}
