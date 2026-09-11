/// 界面偏好：主题模式与货币符号。
///
/// 存储策略与「零额外原生插件」目标一致：偏好随账本写入同一个 JSON 文件，
/// 而不是引入 shared_preferences。
library;

import 'package:flutter/material.dart';

import '../core/result.dart';
import '../data/ledger_repository.dart';

/// 主题模式选项。
enum AppThemeMode {
  /// 跟随系统。
  system,

  /// 浅色。
  light,

  /// 深色。
  dark,
}

/// 主题模式的展示名。
extension AppThemeModeLabel on AppThemeMode {
  /// 中文名称。
  String get label => switch (this) {
        AppThemeMode.system => '跟随系统',
        AppThemeMode.light => '浅色',
        AppThemeMode.dark => '深色',
      };

  /// 对应的 Flutter 主题模式。
  ThemeMode get themeMode => switch (this) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };

  /// 持久化用的英文名。
  String get storageName => name;

  /// 从持久化文本还原。
  static AppThemeMode fromStorage(String? raw) {
    for (final AppThemeMode mode in AppThemeMode.values) {
      if (mode.name == raw) {
        return mode;
      }
    }
    return AppThemeMode.system;
  }
}

/// 偏好键名。
abstract final class PreferenceKeys {
  /// 主题模式。
  static const String themeMode = 'themeMode';

  /// 货币符号。
  static const String currencySymbol = 'currencySymbol';
}

/// 界面偏好状态。
final class SettingsController extends ChangeNotifier {
  /// 构造。
  SettingsController(this._repository);

  final LedgerRepository _repository;

  AppThemeMode _themeMode = AppThemeMode.system;
  String _currencySymbol = '¥';

  /// 主题模式。
  AppThemeMode get themeMode => _themeMode;

  /// 货币符号。
  String get currencySymbol => _currencySymbol;

  /// 从账本中读取已保存的偏好。
  void load() {
    _themeMode = AppThemeModeLabel.fromStorage(
        _repository.preference(PreferenceKeys.themeMode));
    final String? symbol =
        _repository.preference(PreferenceKeys.currencySymbol);
    if (symbol != null && symbol.isNotEmpty) {
      _currencySymbol = symbol;
    }
    notifyListeners();
  }

  /// 设置主题模式。
  Future<Result<Unit>> setThemeMode(AppThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    return _repository.setPreference(
        PreferenceKeys.themeMode, mode.storageName);
  }

  /// 设置货币符号。
  Future<Result<Unit>> setCurrencySymbol(String symbol) async {
    _currencySymbol = symbol;
    notifyListeners();
    return _repository.setPreference(PreferenceKeys.currencySymbol, symbol);
  }
}
