/// CSV 编码工具：按 RFC 4180 处理引号与换行转义。
library;

/// 一行单元格。
typedef CsvRow = List<String>;

/// 把表格编码为 CSV 文本。
///
/// 传入 [bom] 为 true 时在开头写入 UTF-8 BOM，便于 Excel 正确识别中文。
String encodeCsv(List<CsvRow> rows, {bool bom = true}) {
  final StringBuffer buffer = StringBuffer();
  if (bom) {
    buffer.write('\uFEFF');
  }
  for (final CsvRow row in rows) {
    buffer.write(row.map(_escapeCell).join(','));
    buffer.write('\r\n');
  }
  return buffer.toString();
}

/// 解析 CSV 文本为表格，支持引号包裹与其中的换行。
List<CsvRow> decodeCsv(String text) {
  final String source = text.startsWith('\uFEFF') ? text.substring(1) : text;
  final List<CsvRow> rows = <CsvRow>[];
  CsvRow current = <String>[];
  final StringBuffer cell = StringBuffer();
  bool inQuotes = false;

  void endCell() {
    current.add(cell.toString());
    cell.clear();
  }

  void endRow() {
    endCell();
    // 忽略完全空白的尾行。
    if (current.length > 1 || current.first.trim().isNotEmpty) {
      rows.add(current);
    }
    current = <String>[];
  }

  int index = 0;
  while (index < source.length) {
    final String char = source[index];
    if (inQuotes) {
      if (char == '"') {
        final bool escaped =
            index + 1 < source.length && source[index + 1] == '"';
        if (escaped) {
          cell.write('"');
          index += 2;
          continue;
        }
        inQuotes = false;
        index += 1;
        continue;
      }
      cell.write(char);
      index += 1;
      continue;
    }
    switch (char) {
      case '"':
        inQuotes = true;
      case ',':
        endCell();
      case '\r':
        if (index + 1 < source.length && source[index + 1] == '\n') {
          index += 1;
        }
        endRow();
      case '\n':
        endRow();
      default:
        cell.write(char);
    }
    index += 1;
  }

  if (cell.isNotEmpty || current.isNotEmpty) {
    endRow();
  }
  return rows;
}

String _escapeCell(String value) {
  final bool needsQuote = value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  if (!needsQuote) {
    return value;
  }
  return '"${value.replaceAll('"', '""')}"';
}
