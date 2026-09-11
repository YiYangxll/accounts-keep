/// 导入流程编排：解析备份文本 → 生成预览 → 按策略落库。
///
/// 文件选择与写入由 UI 层通过 PlatformBridge 完成，本文件只负责数据校验与合并。
library;

import '../core/result.dart';
import 'import_export.dart';
import 'ledger_data.dart';
import 'ledger_repository.dart';

/// 导入流程编排器。
final class LedgerImporter {
  /// 构造。
  const LedgerImporter(this._repository);

  final LedgerRepository _repository;

  /// 解析备份文本并生成预览。
  Result<({LedgerData data, ImportPreview preview})> prepare(String raw) {
    final Result<({LedgerData data, ArchiveMeta meta})> decoded =
        LedgerTransfer.decodeJson(raw);
    if (decoded.isErr) {
      return Result<({LedgerData data, ImportPreview preview})>.err(
        decoded.error!,
      );
    }
    final ImportPreview preview = LedgerTransfer.preview(
      _repository.data,
      decoded.value.data,
      decoded.value.meta,
    );
    return Result<({LedgerData data, ImportPreview preview})>.ok(
      (data: decoded.value.data, preview: preview),
    );
  }

  /// 按策略把解析后的数据写入仓库，返回实际发生的增删统计。
  ///
  /// [preview] 必须是在写入前基于当前账本生成的预览，统计口径为「导入前 → 导入后」。
  Future<Result<ImportOutcome>> apply(
    LedgerData incoming,
    ImportStrategy strategy, {
    required ImportPreview preview,
  }) async {
    final Result<Unit> written = switch (strategy) {
      ImportStrategy.merge => await _repository.mergeIn(incoming),
      ImportStrategy.replace => await _repository.replaceAll(incoming),
    };
    if (written.isErr) {
      return Result<ImportOutcome>.err(written.error!);
    }
    return Result<ImportOutcome>.ok(outcomeFromPreview(preview, strategy));
  }
}
