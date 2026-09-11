/// 导入导出测试：JSON/CSV 往返、版本校验与合并统计。
library;

import 'package:accounts_keep_test/core/result.dart';
import 'package:accounts_keep_test/data/csv_codec.dart';
import 'package:accounts_keep_test/data/import_export.dart';
import 'package:accounts_keep_test/data/ledger_data.dart';
import 'package:accounts_keep_test/domain/account.dart';
import 'package:accounts_keep_test/domain/category.dart';
import 'package:accounts_keep_test/domain/ledger_error.dart';
import 'package:accounts_keep_test/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

void main() {
  LedgerData sample() => LedgerData(
        accounts: <Account>[
          account(id: 'acc_cash', name: '现金', initialBalanceCents: 10000),
          account(id: 'acc_bank', name: '储蓄卡'),
        ],
        categories: <Category>[category(id: 'cat_food', name: '餐饮')],
        transactions: <Transaction>[
          expense(
            id: 'tx_1',
            amountCents: 1234,
            accountId: 'acc_cash',
            categoryId: 'cat_food',
            occurredAt: DateTime(2026, 3, 10, 12, 30),
            note: '午饭, 带"引号"',
            payee: '食堂',
          ),
        ],
      );

  group('CSV 编码', () {
    test('转义逗号、引号与换行', () {
      const List<CsvRow> rows = <CsvRow>[
        <String>['a', 'b,c', 'd"e', 'f\ng'],
      ];
      final String encoded = encodeCsv(rows, bom: false);
      expect(encoded, 'a,"b,c","d""e","f\ng"\r\n');

      final List<CsvRow> decoded = decodeCsv(encoded);
      expect(decoded.single, <String>['a', 'b,c', 'd"e', 'f\ng']);
    });

    test('默认写入 BOM 以便 Excel 识别中文', () {
      expect(
          encodeCsv(<CsvRow>[
            <String>['中文']
          ]).startsWith('\uFEFF'),
          isTrue);
    });

    test('解析时忽略 BOM 与末尾空行', () {
      final List<CsvRow> rows = decodeCsv('\uFEFFa,b\r\n\r\n');
      expect(rows, <CsvRow>[
        <String>['a', 'b'],
      ]);
    });
  });

  group('导出', () {
    test('JSON 导出包含版本号与统计信息', () {
      final ExportResult result = LedgerTransfer.exportJson(sample(),
          now: DateTime(2026, 3, 15, 10, 30));
      expect(result.fileName, startsWith('ledger_20260315_103000'));
      expect(result.fileName, endsWith('.json'));
      expect(result.content, contains('"schemaVersion": 1'));
      expect(result.content, contains('"transactions": 1'));
      expect(result.content, contains('午饭'));
    });

    test('CSV 导出包含表头与记录，且分类/账户名已翻译', () {
      final ExportResult result = LedgerTransfer.exportCsv(
        sample(),
        now: DateTime(2026, 3, 15, 10, 30),
      );
      expect(result.fileName, endsWith('.csv'));
      final List<CsvRow> rows = decodeCsv(result.content);
      expect(rows.first, contains('日期'));
      expect(rows.first, contains('分类'));
      expect(rows.length, 2);
      final CsvRow record = rows[1];
      expect(record, contains('2026-03-10'));
      expect(record, contains('支出'));
      expect(record, contains('12.34'));
      expect(record, contains('餐饮'));
      expect(record, contains('现金'));
      expect(record, contains('食堂'));
    });

    test('空账本也能导出（仅表头）', () {
      final ExportResult result = LedgerTransfer.exportCsv(const LedgerData(),
          now: DateTime(2026, 3, 15));
      expect(decodeCsv(result.content).length, 1);
    });
  });

  group('JSON 解析与往返', () {
    test('导出再导入内容一致', () {
      final LedgerData original = sample();
      final ExportResult exported = LedgerTransfer.exportJson(original);
      final Result<({LedgerData data, ArchiveMeta meta})> decoded =
          LedgerTransfer.decodeJson(exported.content);

      expect(decoded.isOk, isTrue);
      final LedgerData restored = decoded.value.data;
      expect(restored.accounts.length, 2);
      expect(restored.categories.length, 1);
      expect(restored.transactions.length, 1);
      final Transaction tx = restored.transactions.single;
      expect(tx.amountCents, 1234);
      expect(tx.note, '午饭, 带"引号"');
      // 时间与记账时区偏移都要原样还原，且日期归属不受设备时区影响。
      final DateTime wall = tx.wallClock;
      expect(<int>[wall.year, wall.month, wall.day], <int>[2026, 3, 10]);
      expect(<int>[wall.hour, wall.minute], <int>[12, 30]);
      expect(tx.utcOffsetMinutes, 480);
      expect(decoded.value.meta.transactionCount, 1);
    });

    test('缺少 schemaVersion 被判定为格式错误', () {
      final Result<({LedgerData data, ArchiveMeta meta})> result =
          LedgerTransfer.decodeJson('{"data":{"accounts":[]}}');
      expect(result.isErr, isTrue);
      expect(result.error, isA<MalformedImportError>());
    });

    test('版本过高被拒绝', () {
      final Result<({LedgerData data, ArchiveMeta meta})> result =
          LedgerTransfer.decodeJson(
        '{"schemaVersion":${kLedgerSchemaVersion + 1},"data":{}}',
      );
      expect(result.error, isA<UnsupportedSchemaError>());
    });

    test('非法 JSON 被判定为格式错误', () {
      expect(
        LedgerTransfer.decodeJson('not json').error,
        isA<MalformedImportError>(),
      );
      expect(
        LedgerTransfer.decodeJson('[]').error,
        isA<MalformedImportError>(),
      );
    });

    test('导入时清洗悬空引用', () {
      // 构造一份「流水引用了不存在账户」的数据，导入时应被丢弃并给出告警。
      final LedgerData orphaned = LedgerData(
        accounts: <Account>[account(id: 'acc_alive', name: '现金')],
        categories: <Category>[category(id: 'cat_food', name: '餐饮')],
        transactions: <Transaction>[
          expense(
            id: 'tx_ok',
            amountCents: 100,
            accountId: 'acc_alive',
            categoryId: 'cat_food',
          ),
          expense(
            id: 'tx_orphan',
            amountCents: 200,
            accountId: 'acc_missing',
            categoryId: 'cat_food',
          ),
        ],
      );
      final Result<({LedgerData data, ArchiveMeta meta})> decoded =
          LedgerTransfer.decodeJson(
              LedgerTransfer.exportJson(orphaned).content);
      expect(decoded.isOk, isTrue);
      expect(decoded.value.data.transactions.length, 1);
      expect(decoded.value.data.transactions.single.id, 'tx_ok');
    });
  });

  group('导入预览与统计', () {
    test('全部为新数据', () {
      final ArchiveMeta meta = ArchiveMeta(
        schemaVersion: 1,
        exportedAtUtc: DateTime.utc(2026, 3, 15),
        accountCount: 2,
        categoryCount: 1,
        transactionCount: 1,
      );
      final ImportPreview preview =
          LedgerTransfer.preview(LedgerData.empty, sample(), meta);
      expect(preview.newAccounts, 2);
      expect(preview.overwrittenAccounts, 0);
      expect(preview.newTransactions, 1);
      expect(preview.summary, contains('流水 新增 1 / 覆盖 0'));
    });

    test('同 id 记录计为覆盖', () {
      final LedgerData current = sample();
      final LedgerData incoming = sample().copyWith(
        accounts: <Account>[
          ...sample().accounts,
          account(id: 'a3', name: '支付宝'),
        ],
      );
      final ImportPreview preview = LedgerTransfer.preview(
        current,
        incoming,
        ArchiveMeta(
          schemaVersion: 1,
          exportedAtUtc: DateTime.utc(2026, 3, 15),
          accountCount: 3,
          categoryCount: 1,
          transactionCount: 1,
        ),
      );
      expect(preview.newAccounts, 1);
      expect(preview.overwrittenAccounts, 2);
      expect(preview.newTransactions, 0);
      expect(preview.overwrittenTransactions, 1);
    });

    test('合并策略的统计口径', () {
      final ImportPreview preview = ImportPreview(
        meta: ArchiveMeta(
          schemaVersion: 1,
          exportedAtUtc: DateTime.utc(2026, 3, 15),
          accountCount: 0,
          categoryCount: 0,
          transactionCount: 0,
        ),
        newAccounts: 1,
        overwrittenAccounts: 2,
        newCategories: 0,
        overwrittenCategories: 1,
        newTransactions: 3,
        overwrittenTransactions: 4,
      );
      final ImportOutcome merged =
          outcomeFromPreview(preview, ImportStrategy.merge);
      expect(merged.addedTransactions, 3);
      expect(merged.overwrittenTransactions, 4);
      expect(merged.addedAccounts, 1);
      expect(merged.overwrittenAccounts, 2);

      final ImportOutcome replaced =
          outcomeFromPreview(preview, ImportStrategy.replace);
      expect(replaced.addedTransactions, 7);
      expect(replaced.overwrittenTransactions, 0);
      expect(replaced.addedAccounts, 3);
      expect(replaced.addedCategories, 1);
    });
  });
}
