/// 平台能力出口：整个工程中唯一直接依赖原生插件的模块。
///
/// 鸿蒙或其他平台迁移时，只需替换本文件的实现（或提供一个同接口的
/// `PlatformBridge` 变体），domain/data/ui 三层无需改动。
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 平台能力集合。
final class PlatformBridge {
  /// 构造。
  const PlatformBridge();

  /// 应用私有文档目录：账本数据与导出结果的存放位置。
  ///
  /// 该目录不会被系统自动清理（区别于缓存目录），且无需任何存储权限。
  Future<Directory> documentsDirectory() async {
    final Directory dir = await getApplicationDocumentsDirectory();
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }
}
