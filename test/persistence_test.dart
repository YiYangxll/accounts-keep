/// 存储层测试：原子写入、往返一致、损坏回退与版本校验。
library;

import 'dart:convert';
import 'dart:io';

import 'package:accounts_keep_test/core/result.dart';
import 'package:accounts_keep_test/data/ledger_data.dart';
import 'package:accounts_keep_test/data/storage/ledger_storage.dart';
import 'package:accounts_keep_test/domain/account.dart';
import 'package:accounts_keep_test/domain/category.dart';
import 'package:accounts_keep_test/domain/ledger_error.dart';
import 'package:accounts_keep_test/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

void main() {
  late Directory dir;
  late LedgerStorage storage;
  late File ledgerFile;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ledger_storage_test_');
    storage = LedgerStorage(documentsDirectoryProvider: () async => dir);
    ledgerFile = File('${dir.path}${Platform.pathSeparator}accounts_keep'
        '${Platform.pathSeparator}ledger.json');
  });

  tearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  LedgerData sampleData() {
    final Account cash = account(
      id: 'acc_cash',
      name: '现金',
      initialBalanceCents: 10000,
    );
    final Category food = category(id: 'cat_food', name: '餐饮');
    return LedgerData(
      accounts: <Account>[cash],
      categories: <Category>[food],
      transactions: <Transaction>[
        expense(
          id: 'tx_1',
          amountCents: 1234,
          accountId: 'acc_cash',
          categoryId: 'cat_food',
          occurredAt: DateTime(2026, 3, 10, 12, 30),
          note: '午饭',
        ),
      ],
      preferences: const <String, String>{'currencySymbol': '¥'},
    );
  }

  group('读写往返', () {
    test('文件不存在时返回空账本', () async {
      final Result<StorageReadResult> result = await storage.read();
      expect(result.isOk, isTrue);
      expect(result.value.data.accounts, isEmpty);
      expect(result.value.data.transactions, isEmpty);
      expect(result.value.warnings, isEmpty);
    });

    test('写入后重新读取内容一致', () async {
      final Result<Unit> written = await storage.write(sampleData());
      expect(written.isOk, isTrue);
      expect(ledgerFile.existsSync(), isTrue);

      final Result<StorageReadResult> read = await storage.read();
      expect(read.isOk, isTrue);
      final LedgerData loaded = read.value.data;
      expect(loaded.accounts.single.name, '现金');
      expect(loaded.categories.single.name, '餐饮');
      expect(loaded.transactions.single.amountCents, 1234);
      expect(loaded.transactions.single.note, '午饭');
      // wallClock 是「用户当时看到的墙上时间」，比较组件而不是时区标记或 epoch。
      final DateTime wall = loaded.transactions.single.wallClock;
      expect(<int>[wall.year, wall.month, wall.day], <int>[2026, 3, 10]);
      expect(<int>[wall.hour, wall.minute], <int>[12, 30]);
      expect(loaded.transactions.single.utcOffsetMinutes, 480);
      expect(loaded.preferences['currencySymbol'], '¥');
    });

    test('时间以 UTC 形式落盘', () async {
      await storage.write(sampleData());
      final Map<String, Object?> json =
          jsonDecode(ledgerFile.readAsStringSync()) as Map<String, Object?>;
      final Map<String, Object?> payload =
          json['data']! as Map<String, Object?>;
      expect(json['schemaVersion'], kLedgerSchemaVersion);
      final List<Object?> transactions =
          payload['transactions']! as List<Object?>;
      final Map<String, Object?> first =
          transactions.first! as Map<String, Object?>;
      transactions.first! as Map<String, Object?>;
      expect(first['occurredAtUtc'], endsWith('Z'));
    });

    test('落盘 JSON 带 schemaVersion', () async {
      await storage.write(sampleData());
      final Map<String, Object?> json =
          jsonDecode(ledgerFile.readAsStringSync()) as Map<String, Object?>;
      expect(json['schemaVersion'], kLedgerSchemaVersion);
    });

    test('不留下临时文件', () async {
      await storage.write(sampleData());
      final File temp = File('${ledgerFile.path}.tmp');
      expect(temp.existsSync(), isFalse);
    });

    test('第二次写入会生成备份文件', () async {
      await storage.write(sampleData());
      await storage.write(sampleData().copyWith(accounts: <Account>[]));
      expect(File('${ledgerFile.path}.bak').existsSync(), isTrue);
    });
  });

  group('损坏与恢复', () {
    test('损坏文件回退到备份', () async {
      // 先写入两份数据，确保备份存在且内容可用。
      await storage.write(sampleData());
      final LedgerData second =
          sampleData().copyWith(transactions: <Transaction>[]);
      await storage.write(second);

      // 破坏主文件。
      ledgerFile.writeAsStringSync('{ this is not json');

      final Result<StorageReadResult> read = await storage.read();
      expect(read.isOk, isTrue);
      expect(read.value.recoveredFromBackup, isTrue);
      expect(read.value.warnings, isNotEmpty);
      // 备份是上一份数据（含一条流水）。
      expect(read.value.data.transactions, isNotEmpty);
    });

    test('损坏文件被留档为 .corrupt-*', () async {
      await storage.write(sampleData());
      ledgerFile.writeAsStringSync('garbage');
      await storage.read();
      final List<File> corrupt = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.contains('.corrupt-'))
          .toList();
      expect(corrupt, isNotEmpty);
    });

    test('主文件与备份都损坏时返回空账本并给出告警', () async {
      await storage.write(sampleData());
      await storage.write(sampleData());
      ledgerFile.writeAsStringSync('garbage');
      File('${ledgerFile.path}.bak').writeAsStringSync('also garbage');

      final Result<StorageReadResult> read = await storage.read();
      expect(read.isOk, isTrue);
      expect(read.value.data.transactions, isEmpty);
      expect(read.value.warnings.join(), contains('损坏'));
    });

    test('空文件视为损坏', () async {
      await storage.write(sampleData());
      ledgerFile.writeAsStringSync('   ');
      final Result<StorageReadResult> read = await storage.read();
      expect(read.isOk, isTrue);
      expect(read.value.warnings, isNotEmpty);
    });

    test('数据中悬空引用会被清洗并给出告警', () async {
      final LedgerData broken = LedgerData(
        accounts: <Account>[account(id: 'a', name: '现金')],
        categories: <Category>[category(id: 'c', name: '餐饮')],
        transactions: <Transaction>[
          expense(
            id: 'ok',
            amountCents: 100,
            accountId: 'a',
            categoryId: 'c',
          ),
          expense(
            id: 'orphan',
            amountCents: 200,
            accountId: 'missing',
            categoryId: 'c',
          ),
          expense(
            id: 'badAmount',
            amountCents: 0,
            accountId: 'a',
            categoryId: 'c',
          ),
        ],
      );
      await storage.write(broken);

      final Result<StorageReadResult> read = await storage.read();
      expect(read.isOk, isTrue);
      expect(read.value.data.transactions.length, 1);
      expect(read.value.data.transactions.single.id, 'ok');
      expect(read.value.warnings.length, 2);
    });

    test('未来版本的数据被拒绝，并回退到备份而非误读', () async {
      // 写两次以产生 .bak（内容为当前版本）。
      await storage.write(sampleData());
      await storage.write(sampleData());
      final Map<String, Object?> json =
          jsonDecode(ledgerFile.readAsStringSync()) as Map<String, Object?>;
      json['schemaVersion'] = kLedgerSchemaVersion + 1;
      ledgerFile.writeAsStringSync(jsonEncode(json));

      final Result<LedgerData> direct = storage.decodeForTest(
        ledgerFile.readAsStringSync(),
      );
      expect(direct.isErr, isTrue);
      expect(direct.error, isA<UnsupportedSchemaError>());

      // 主文件被拒绝后应回退到 .bak，并保留可用数据。
      final Result<StorageReadResult> read = await storage.read();
      expect(read.isOk, isTrue);
      expect(read.value.recoveredFromBackup, isTrue);
      expect(read.value.data.transactions, isNotEmpty);
    });
  });

  group('清空与导出目录', () {
    test('deleteAll 删除主文件与备份', () async {
      await storage.write(sampleData());
      await storage.write(sampleData());
      expect(File('${ledgerFile.path}.bak').existsSync(), isTrue);

      final Result<Unit> deleted = await storage.deleteAll();
      expect(deleted.isOk, isTrue);
      expect(ledgerFile.existsSync(), isFalse);
      expect(File('${ledgerFile.path}.bak').existsSync(), isFalse);

      final Result<StorageReadResult> read = await storage.read();
      expect(read.value.data.accounts, isEmpty);
    });

    test('writeExport 写入导出目录', () async {
      final Result<File> written =
          await storage.writeExport('ledger_20260315.json', '{"a":1}');
      expect(written.isOk, isTrue);
      expect(written.value.existsSync(), isTrue);
      expect(written.value.readAsStringSync(), '{"a":1}');
      expect(written.value.path, contains('exports'));
    });
  });
}
