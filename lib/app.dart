/// 应用根组件：主题、中文本地化与路由。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'data/ledger_repository.dart';
import 'domain/enums.dart';
import 'domain/transaction.dart';
import 'state/settings_controller.dart';
import 'ui/entry/transaction_editor_page.dart';
import 'ui/shell/home_shell.dart';
import 'ui/theme/app_theme.dart';

/// 记账应用根组件。
class AccountsKeepApp extends StatelessWidget {
  /// 构造。
  const AccountsKeepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SettingsController>(
      create: (BuildContext context) =>
          SettingsController(context.read<LedgerRepository>())..load(),
      child: Consumer<SettingsController>(
        builder: (BuildContext context, SettingsController settings, _) {
          return MaterialApp(
            title: '记账本',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: settings.themeMode.themeMode,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const <Locale>[
              Locale('zh', 'CN'),
              Locale('en', 'US'),
            ],
            localizationsDelegates: const <LocalizationsDelegate<Object>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const HomeShell(),
            onGenerateRoute: (RouteSettings routeSettings) {
              if (routeSettings.name == TransactionEditorPage.routeName) {
                final Object? args = routeSettings.arguments;
                return MaterialPageRoute<void>(
                  builder: (BuildContext context) => TransactionEditorPage(
                    existing: args is Transaction ? args : null,
                    initialKind: args is TxKind ? args : null,
                  ),
                  settings: routeSettings,
                );
              }
              return null;
            },
          );
        },
      ),
    );
  }
}
