/// 测试公共设施：真实落地到临时目录的账本仓库与固定时钟。
library;

import 'dart:io';

import 'package:accounts_keep/data/ledger_repository.dart';
import 'package:accounts_keep/data/storage/ledger_storage.dart';
import 'package:accounts_keep/domain/account.dart';
import 'package:accounts_keep/domain/category.dart';
import 'package:accounts_keep/domain/enums.dart';
import 'package:accounts_keep/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

/// 测试期间固定使用的时间（本地时区解释）。
final DateTime kTestNow = DateTime(2026, 3, 15, 12);

/// 固定时钟，供需要注入时间的组件使用。
DateTime fixedClock() => kTestNow;

/// 在 `testWidgets` 里做**真实文件 I/O** 的逃生口。
///
/// 背景：`testWidgets` 的测试体跑在 Flutter 的 fake async 区里，`dart:io`
/// 的真实异步操作在其中永远不会完成 —— 表现为测试直接卡死到超时（不是抛异常，
/// 极难排查）。仓库的 read/write 都要落盘，所以凡是在 `testWidgets` 测试体里
/// **直接调用仓库或建 TestLedger**，都必须用它包一层。
///
/// 通过**界面交互**触发的写入不需要包（那些发生在 tester 自己的 zone 里）。
///
/// ```dart
/// final TestLedger ledger = (await runIo(tester, TestLedger.create))!;
/// await runIo(tester, () => ledger.repository.addTransaction(tx));
/// ```
Future<T?> runIo<T>(WidgetTester tester, Future<T> Function() action) =>
    tester.runAsync(action);

/// 一个绑定临时目录的测试账本。
final class TestLedger {
  TestLedger._(this.tempDir, this.storage, this.repository);

  /// 创建并初始化。
  static Future<TestLedger> create({DateTime? now}) async {
    final Directory dir = await Directory.systemTemp.createTemp('ledger_test_');
    final LedgerStorage storage = LedgerStorage(
      documentsDirectoryProvider: () async => dir,
    );
    final int seed = DateTime.now().microsecondsSinceEpoch;
    int counter = 0;
    final LedgerRepository repository = LedgerRepository(
      storage,
      idGenerator: () => 'id_${seed}_${counter++}',
      clock: () => now ?? kTestNow,
    );
    await repository.load();
    return TestLedger._(dir, storage, repository);
  }

  /// 临时目录，需在 tearDown 中清理。
  final Directory tempDir;

  /// 存储层。
  final LedgerStorage storage;

  /// 仓库。
  final LedgerRepository repository;

  /// 便捷取默认账户 id。
  ///
  /// 注意：它读取的是「当前列表的第一个账户」，账户被删除后返回值会变化。
  /// 在涉及增删账户的测试中，请先把它取到局部变量里再使用。
  String get cashId => repository.data.accounts.first.id;

  /// 清理临时目录。
  ///
  /// Windows 上文件句柄释放有延迟，删除失败时重试若干次，避免把清理失败
  /// 误报成测试失败。
  Future<void> dispose() async {
    repository.dispose();
    for (int attempt = 0; attempt < 5; attempt++) {
      if (!tempDir.existsSync()) {
        return;
      }
      try {
        tempDir.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    }
  }
}

/// 构造一笔支出。
Transaction expense({
  required String id,
  required int amountCents,
  required String accountId,
  required String categoryId,
  DateTime? occurredAt,
  String? note,
  String? payee,
  int? offsetMinutes,
}) {
  final DateTime local = occurredAt ?? kTestNow;
  return Transaction(
    id: id,
    kind: TxKind.expense,
    amountCents: amountCents,
    accountId: accountId,
    categoryId: categoryId,
    occurredAtUtc: local.toUtc(),
    utcOffsetMinutes: offsetMinutes ?? local.timeZoneOffset.inMinutes,
    note: note,
    payee: payee,
  );
}

/// 构造一笔收入。
Transaction income({
  required String id,
  required int amountCents,
  required String accountId,
  required String categoryId,
  DateTime? occurredAt,
  String? note,
}) {
  final DateTime local = occurredAt ?? kTestNow;
  return Transaction(
    id: id,
    kind: TxKind.income,
    amountCents: amountCents,
    accountId: accountId,
    categoryId: categoryId,
    occurredAtUtc: local.toUtc(),
    utcOffsetMinutes: local.timeZoneOffset.inMinutes,
    note: note,
  );
}

/// 构造一笔转账。
Transaction transfer({
  required String id,
  required int amountCents,
  required String fromAccountId,
  required String toAccountId,
  DateTime? occurredAt,
  int feeCents = 0,
}) {
  final DateTime local = occurredAt ?? kTestNow;
  return Transaction(
    id: id,
    kind: TxKind.transfer,
    amountCents: amountCents,
    accountId: fromAccountId,
    toAccountId: toAccountId,
    feeCents: feeCents,
    occurredAtUtc: local.toUtc(),
    utcOffsetMinutes: local.timeZoneOffset.inMinutes,
  );
}

/// 构造账户。
Account account({
  required String id,
  required String name,
  AccountKind kind = AccountKind.cash,
  int initialBalanceCents = 0,
  int sortOrder = 0,
}) {
  return Account(
    id: id,
    name: name,
    kind: kind,
    initialBalanceCents: initialBalanceCents,
    sortOrder: sortOrder,
  );
}

/// 构造分类。
Category category({
  required String id,
  required String name,
  CategoryKind kind = CategoryKind.expense,
  int sortOrder = 0,
}) {
  return Category(id: id, name: name, kind: kind, sortOrder: sortOrder);
}
