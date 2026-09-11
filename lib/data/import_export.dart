/// 数据导入导出：JSON 完整备份与 CSV 流水表。
///
/// 设计取舍见 docs/data_format.md：
/// * JSON 为权威备份格式，携带 schemaVersion，可完整还原；
/// * CSV 为可读/可编辑格式，只承载流水，便于在 Excel 中查看与整理。
library;

import 'dart:convert';

import '../core/date_x.dart';
import '../core/json_x.dart';
import '../core/money.dart';
import '../core/result.dart';
import '../domain/account.dart';
import '../domain/category.dart';
import '../domain/enums.dart';
import '../domain/ledger_error.dart';
import '../domain/transaction.dart';
import 'csv_codec.dart';
import 'ledger_data.dart';

/// 备份文件的元信息。
final class ArchiveMeta {
  /// 构造。
  const ArchiveMeta({
    required this.schemaVersion,
    required this.exportedAtUtc,
    required this.accountCount,
    required this.categoryCount,
    required this.transactionCount,
  });

  /// 数据版本。
  final int schemaVersion;

  /// 导出时间。
  final DateTime exportedAtUtc;

  /// 账户数。
  final int accountCount;

  /// 分类数。
  final int categoryCount;

  /// 流水数。
  final int transactionCount;
}

/// 导入预览：让用户在真正写入前看清会发生什么。
final class ImportPreview {
  /// 构造。
  const ImportPreview({
    required this.meta,
    required this.newAccounts,
    required this.overwrittenAccounts,
    required this.newCategories,
    required this.overwrittenCategories,
    required this.newTransactions,
    required this.overwrittenTransactions,
  });

  /// 备份元信息。
  final ArchiveMeta meta;

  /// 将新增的账户数。
  final int newAccounts;

  /// 将被覆盖的账户数。
  final int overwrittenAccounts;

  /// 将新增的分类数。
  final int newCategories;

  /// 将被覆盖的分类数。
  final int overwrittenCategories;

  /// 将新增的流水数。
  final int newTransactions;

  /// 将被覆盖的流水数。
  final int overwrittenTransactions;

  /// 摘要文案。
  String get summary => '流水 新增 $newTransactions / 覆盖 $overwrittenTransactions；'
      '账户 新增 $newAccounts / 覆盖 $overwrittenAccounts；'
      '分类 新增 $newCategories / 覆盖 $overwrittenCategories';
}

/// 导入结果统计。
final class ImportOutcome {
  /// 构造。
  const ImportOutcome({
    required this.addedTransactions,
    required this.overwrittenTransactions,
    required this.addedAccounts,
    required this.overwrittenAccounts,
    required this.addedCategories,
    required this.overwrittenCategories,
  });

  /// 新增流水数。
  final int addedTransactions;

  /// 覆盖流水数。
  final int overwrittenTransactions;

  /// 新增账户数。
  final int addedAccounts;

  /// 覆盖账户数。
  final int overwrittenAccounts;

  /// 新增分类数。
  final int addedCategories;

  /// 覆盖分类数。
  final int overwrittenCategories;
}

/// 导入合并策略。
enum ImportStrategy {
  /// 与现有数据合并，同 id 记录以导入数据为准。
  merge,

  /// 用导入数据完全替换现有数据。
  replace,
}

/// 导入导出的结果载体。
final class ExportResult {
  /// 构造。
  const ExportResult({required this.fileName, required this.content});

  /// 建议的文件名。
  final String fileName;

  /// 文件内容。
  final String content;
}

/// 数据导入导出服务（纯函数，不触碰文件系统，便于测试）。
abstract final class LedgerTransfer {
  /// 导出完整 JSON 备份。
  ///
  /// 与落盘使用同一个信封格式（见 [LedgerData.toEnvelopeJson]），
  /// 因此备份内容可以直接当作账本文件使用。
  static ExportResult exportJson(LedgerData data, {DateTime? now}) {
    final DateTime stamp = (now ?? DateTime.now()).toUtc();
    return ExportResult(
      fileName: 'ledger_${_fileStamp(stamp)}.json',
      content: const JsonEncoder.withIndent('  ')
          .convert(data.toEnvelopeJson(exportedAtUtc: stamp)),
    );
  }

  /// 导出流水 CSV。
  static ExportResult exportCsv(
    LedgerData data, {
    DateTime? now,
    String currencySymbol = '¥',
  }) {
    final Map<String, String> accountNames = <String, String>{
      for (final Account a in data.accounts) a.id: a.name,
    };
    final Map<String, String> categoryNames = <String, String>{
      for (final Category c in data.categories) c.id: c.name,
    };
    final List<Transaction> sorted = List<Transaction>.of(data.transactions)
      ..sort(
          (Transaction a, Transaction b) => a.wallClock.compareTo(b.wallClock));

    final List<CsvRow> rows = <CsvRow>[
      <String>[
        '日期',
        '时间',
        '类型',
        '金额($currencySymbol)',
        '分类',
        '账户',
        '转入账户',
        '手续费($currencySymbol)',
        '交易对象',
        '备注',
        '标签',
        '是否删除',
      ],
    ];
    for (final Transaction t in sorted) {
      final DateTime local = t.wallClock;
      rows.add(<String>[
        local.dateText,
        '${local.hour.toString().padLeft(2, '0')}:'
            '${local.minute.toString().padLeft(2, '0')}',
        t.kind.label,
        Money.toPlainString(t.amountCents),
        categoryNames[t.categoryId] ?? '',
        accountNames[t.accountId] ?? '',
        accountNames[t.toAccountId] ?? '',
        Money.toPlainString(t.feeCents),
        t.payee ?? '',
        t.note ?? '',
        t.tag ?? '',
        t.isDeleted ? '是' : '否',
      ]);
    }
    final DateTime stamp = (now ?? DateTime.now()).toUtc();
    return ExportResult(
      fileName: 'ledger_${_fileStamp(stamp)}.csv',
      content: encodeCsv(rows),
    );
  }

  /// 解析 JSON 备份文本，返回数据与元信息。
  static Result<({LedgerData data, ArchiveMeta meta})> decodeJson(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      return Result<({LedgerData data, ArchiveMeta meta})>.err(
        MalformedImportError('文件不是合法 JSON：${e.message}'),
      );
    }
    if (decoded is! Map<Object?, Object?>) {
      return const Result<({LedgerData data, ArchiveMeta meta})>.err(
        MalformedImportError('文件顶层结构不是对象'),
      );
    }
    final Map<String, Object?> json = decoded
        .map((Object? k, Object? v) => MapEntry<String, Object?>('$k', v));

    final int schemaVersion = json.optionalInt('schemaVersion') ?? 0;
    if (schemaVersion == 0) {
      return const Result<({LedgerData data, ArchiveMeta meta})>.err(
        MalformedImportError('缺少 schemaVersion 字段，无法确认数据版本'),
      );
    }
    if (schemaVersion > kLedgerSchemaVersion) {
      return Result<({LedgerData data, ArchiveMeta meta})>.err(
        UnsupportedSchemaError(schemaVersion, kLedgerSchemaVersion),
      );
    }

    final LedgerData data;
    try {
      final Map<String, Object?> payload = json.optionalMap('data') ?? json;
      data = LedgerData.fromJson(payload);
    } on LedgerError catch (e) {
      return Result<({LedgerData data, ArchiveMeta meta})>.err(e);
    }

    final ({LedgerData data, List<String> warnings}) cleaned = data.sanitize();
    return Result<({LedgerData data, ArchiveMeta meta})>.ok((
      data: cleaned.data,
      meta: ArchiveMeta(
        schemaVersion: schemaVersion,
        exportedAtUtc:
            json.optionalDateTime('exportedAtUtc') ?? DateTime.now().toUtc(),
        accountCount: cleaned.data.accounts.length,
        categoryCount: cleaned.data.categories.length,
        transactionCount: cleaned.data.transactions.length,
      ),
    ));
  }

  /// 生成导入预览。
  static ImportPreview preview(
      LedgerData current, LedgerData incoming, ArchiveMeta meta) {
    final Set<String> accountIds =
        current.accounts.map((Account a) => a.id).toSet();
    final Set<String> categoryIds =
        current.categories.map((Category c) => c.id).toSet();
    final Set<String> transactionIds =
        current.transactions.map((Transaction t) => t.id).toSet();

    int overwrittenAccounts = 0;
    for (final Account a in incoming.accounts) {
      if (accountIds.contains(a.id)) {
        overwrittenAccounts += 1;
      }
    }
    int overwrittenCategories = 0;
    for (final Category c in incoming.categories) {
      if (categoryIds.contains(c.id)) {
        overwrittenCategories += 1;
      }
    }
    int overwrittenTransactions = 0;
    for (final Transaction t in incoming.transactions) {
      if (transactionIds.contains(t.id)) {
        overwrittenTransactions += 1;
      }
    }

    return ImportPreview(
      meta: meta,
      newAccounts: incoming.accounts.length - overwrittenAccounts,
      overwrittenAccounts: overwrittenAccounts,
      newCategories: incoming.categories.length - overwrittenCategories,
      overwrittenCategories: overwrittenCategories,
      newTransactions: incoming.transactions.length - overwrittenTransactions,
      overwrittenTransactions: overwrittenTransactions,
    );
  }
}

/// 把导入预览换算成实际落库统计。
ImportOutcome outcomeFromPreview(
    ImportPreview preview, ImportStrategy strategy) {
  if (strategy == ImportStrategy.replace) {
    return ImportOutcome(
      addedTransactions:
          preview.newTransactions + preview.overwrittenTransactions,
      overwrittenTransactions: 0,
      addedAccounts: preview.newAccounts + preview.overwrittenAccounts,
      overwrittenAccounts: 0,
      addedCategories: preview.newCategories + preview.overwrittenCategories,
      overwrittenCategories: 0,
    );
  }
  return ImportOutcome(
    addedTransactions: preview.newTransactions,
    overwrittenTransactions: preview.overwrittenTransactions,
    addedAccounts: preview.newAccounts,
    overwrittenAccounts: preview.overwrittenAccounts,
    addedCategories: preview.newCategories,
    overwrittenCategories: preview.overwrittenCategories,
  );
}

String _fileStamp(DateTime utc) {
  final DateTime local = utc.toLocal();
  return '${local.dateText.replaceAll('-', '')}_'
      '${local.hour.toString().padLeft(2, '0')}'
      '${local.minute.toString().padLeft(2, '0')}'
      '${local.second.toString().padLeft(2, '0')}';
}
