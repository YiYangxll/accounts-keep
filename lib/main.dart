/// 应用入口：加载本地账本后启动界面。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/platform_bridge.dart';
import 'data/ledger_repository.dart';
import 'data/storage/ledger_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const PlatformBridge bridge = PlatformBridge();
  final LedgerRepository repository = LedgerRepository(
    LedgerStorage(documentsDirectoryProvider: bridge.documentsDirectory),
  );
  await repository.load();

  runApp(
    ChangeNotifierProvider<LedgerRepository>.value(
      value: repository,
      child: const AccountsKeepApp(),
    ),
  );
}
