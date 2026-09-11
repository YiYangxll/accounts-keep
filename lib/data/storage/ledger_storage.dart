/// 本地文件存储：单文件 JSON + 原子写入 + 备份回退。
///
/// 设计取舍见 docs/data_format.md：
/// * 单文件便于备份、迁移与整体导入导出；
/// * 原子写入（写临时文件后 rename）避免断电/杀进程导致半截文件；
/// * 保留一份 `.bak` 作为读取失败时的回退。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../core/json_x.dart';
import '../../core/result.dart';
import '../../domain/ledger_error.dart';
import '../ledger_data.dart';

/// 应用文档目录提供者，便于测试注入与平台替换。
typedef DocumentsDirectoryProvider = Future<Directory> Function();

/// 读取结果，附带可展示给用户的诊断信息。
final class StorageReadResult {
  /// 构造。
  const StorageReadResult({
    required this.data,
    required this.warnings,
    required this.recoveredFromBackup,
  });

  /// 读取到的账本数据。
  final LedgerData data;

  /// 读取过程中的告警（数据自愈、回退等）。
  final List<String> warnings;

  /// 是否从备份文件恢复。
  final bool recoveredFromBackup;
}

/// 账本文件存储。
///
/// 刻意不加 `final`：测试用子类覆写 [write]/[read] 来模拟磁盘故障，
/// 从而验证仓库在落盘失败时的回滚行为（生产代码请勿继承此类）。
class LedgerStorage {
  /// 构造。
  LedgerStorage({
    required DocumentsDirectoryProvider documentsDirectoryProvider,
    this.directoryName = 'accounts_keep',
    this.fileName = 'ledger.json',
  }) : _documentsDirectory = documentsDirectoryProvider;

  final DocumentsDirectoryProvider _documentsDirectory;

  /// 账本所在子目录名。
  final String directoryName;

  /// 账本文件名。
  final String fileName;

  File? _cachedFile;

  /// 读取账本。
  ///
  /// 文件不存在时返回空账本（首次启动）。解析失败时依次尝试：
  /// 备份文件 → 把损坏文件改名留档 → 空账本。
  Future<Result<StorageReadResult>> read() async {
    try {
      final File file = await _resolveFile();
      if (!file.existsSync()) {
        return const Result<StorageReadResult>.ok(
          StorageReadResult(
            data: LedgerData.empty,
            warnings: <String>[],
            recoveredFromBackup: false,
          ),
        );
      }

      final String raw = await file.readAsString();
      final Result<LedgerData> primary = _decode(raw);
      if (primary.isOk) {
        final ({LedgerData data, List<String> warnings}) cleaned =
            primary.value.sanitize();
        return Result<StorageReadResult>.ok(
          StorageReadResult(
            data: cleaned.data,
            warnings: cleaned.warnings,
            recoveredFromBackup: false,
          ),
        );
      }

      final File backup = _backupFileFor(file);
      final List<String> warnings = <String>[
        '账本文件损坏（${primary.error!.message}），已尝试从备份恢复。',
      ];
      if (backup.existsSync()) {
        final Result<LedgerData> fromBackup =
            _decode(await backup.readAsString());
        if (fromBackup.isOk) {
          await _quarantine(file);
          final ({LedgerData data, List<String> warnings}) cleaned =
              fromBackup.value.sanitize();
          warnings.addAll(cleaned.warnings);
          warnings.add('已从备份恢复最近一次数据。');
          return Result<StorageReadResult>.ok(
            StorageReadResult(
              data: cleaned.data,
              warnings: warnings,
              recoveredFromBackup: true,
            ),
          );
        }
        warnings.add('备份文件同样无法解析。');
      } else {
        warnings.add('没有可用备份。');
      }

      await _quarantine(file);
      return Result<StorageReadResult>.ok(
        StorageReadResult(
          data: LedgerData.empty,
          warnings: warnings,
          recoveredFromBackup: false,
        ),
      );
    } on FileSystemException catch (e) {
      return Result<StorageReadResult>.err(
        StorageError('读取账本失败：${e.message}', cause: e),
      );
    } on LedgerError catch (e) {
      return Result<StorageReadResult>.err(e);
    }
  }

  /// 原子写入账本。
  Future<Result<Unit>> write(LedgerData data) async {
    try {
      final File file = await _resolveFile();
      final File temp = File('${file.path}.tmp');
      if (temp.existsSync()) {
        temp.deleteSync();
      }
      await temp.writeAsString(data.encode(), flush: true);
      if (file.existsSync()) {
        file.copySync(_backupFileFor(file).path);
        file.deleteSync();
      }
      await temp.rename(file.path);
      return const Result<Unit>.ok(Unit());
    } on FileSystemException catch (e) {
      return Result<Unit>.err(
        StorageError('保存账本失败：${e.message}', cause: e),
      );
    }
  }

  /// 删除账本与备份（用于「清空全部数据」）。
  Future<Result<Unit>> deleteAll() async {
    try {
      final File file = await _resolveFile();
      for (final File target in <File>[
        file,
        File('${file.path}.tmp'),
        _backupFileFor(file),
      ]) {
        if (target.existsSync()) {
          target.deleteSync();
        }
      }
      return const Result<Unit>.ok(Unit());
    } on FileSystemException catch (e) {
      return Result<Unit>.err(
        StorageError('清空数据失败：${e.message}', cause: e),
      );
    }
  }

  /// 导出目录（与账本同目录），便于用户通过文件管理器取走备份。
  Future<Result<Directory>> exportDirectory() async {
    try {
      final File file = await _resolveFile();
      final Directory dir = Directory(
        '${file.parent.path}${Platform.pathSeparator}exports',
      );
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return Result<Directory>.ok(dir);
    } on FileSystemException catch (e) {
      return Result<Directory>.err(
        StorageError('创建导出目录失败：${e.message}', cause: e),
      );
    }
  }

  /// 把文本写入导出目录，返回写入的文件。
  Future<Result<File>> writeExport(String fileName, String content) async {
    final Result<Directory> dir = await exportDirectory();
    if (dir.isErr) {
      return Result<File>.err(dir.error!);
    }
    try {
      final File file = File(
        '${dir.value.path}${Platform.pathSeparator}$fileName',
      );
      await file.writeAsString(content, flush: true);
      return Result<File>.ok(file);
    } on FileSystemException catch (e) {
      return Result<File>.err(
        StorageError('写入导出文件失败：${e.message}', cause: e),
      );
    }
  }

  Result<LedgerData> _decode(String raw) {
    if (raw.trim().isEmpty) {
      return const Result<LedgerData>.err(CorruptDataError('账本文件内容为空'));
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      return Result<LedgerData>.err(
        CorruptDataError('账本不是合法 JSON：${e.message}', cause: e),
      );
    }
    if (decoded is! Map<Object?, Object?>) {
      return const Result<LedgerData>.err(CorruptDataError('账本顶层结构不是对象'));
    }
    final Map<String, Object?> json = decoded
        .map((Object? k, Object? v) => MapEntry<String, Object?>('$k', v));

    // 注意：JSON 数字经 jsonDecode 后是 num，必须通过 optionalInt 归一化，
    // 否则 `is int` 判断会失败并静默按当前版本处理，从而放过未来版本的数据。
    final int schemaVersion =
        json.optionalInt('schemaVersion') ?? kLedgerSchemaVersion;
    if (schemaVersion > kLedgerSchemaVersion) {
      return Result<LedgerData>.err(
        UnsupportedSchemaError(schemaVersion, kLedgerSchemaVersion),
      );
    }

    try {
      final Object? payload = json['data'];
      final Map<String, Object?> dataJson = payload is Map<Object?, Object?>
          ? payload.map(
              (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
            )
          : json;
      return Result<LedgerData>.ok(LedgerData.fromJson(dataJson));
    } on LedgerError catch (e) {
      return Result<LedgerData>.err(e);
    }
  }

  /// 解析账本文本（暴露给测试，业务代码请用 [read]）。
  @visibleForTesting
  Result<LedgerData> decodeForTest(String raw) => _decode(raw);

  Future<File> _resolveFile() async {
    final File? cached = _cachedFile;
    if (cached != null) {
      return cached;
    }
    final Directory documents = await _documentsDirectory();
    final Directory dir = Directory(
      '${documents.path}${Platform.pathSeparator}$directoryName',
    );
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final File file = File('${dir.path}${Platform.pathSeparator}$fileName');
    _cachedFile = file;
    return file;
  }

  File _backupFileFor(File file) => File('${file.path}.bak');

  Future<void> _quarantine(File file) async {
    try {
      final String stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      file.renameSync('${file.path}.corrupt-$stamp');
    } on FileSystemException {
      // 留档失败不应阻断启动，忽略即可。
    }
  }
}
