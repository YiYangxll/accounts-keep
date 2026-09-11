/// 应用主题：统一配色、卡片圆角与中文字体回退。
library;

import 'package:flutter/material.dart';

/// 主题定义。
abstract final class AppTheme {
  /// 品牌主色（记账场景偏稳重的青绿色）。
  static const Color seedColor = Color(0xFF12897A);

  /// 支出色（红）。
  static const Color expenseColor = Color(0xFFD93F3F);

  /// 收入色（绿）。
  static const Color incomeColor = Color(0xFF1F9D55);

  /// 转账色（蓝）。
  static const Color transferColor = Color(0xFF2F6FED);

  /// 浅色主题。
  static ThemeData light() => _build(Brightness.light);

  /// 深色主题。
  static ThemeData dark() => _build(Brightness.dark);

  /// 根据收支方向返回语义色。
  static Color amountColor(BuildContext context, int cents) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    if (cents > 0) {
      return incomeColor;
    }
    if (cents < 0) {
      return expenseColor;
    }
    return scheme.onSurfaceVariant;
  }

  static ThemeData _build(Brightness brightness) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    final bool isLight = brightness == Brightness.light;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isLight ? const Color(0xFFF6F7F9) : scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: isLight ? const Color(0xFFF6F7F9) : scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: isLight ? Colors.white : scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? Colors.white : scheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: scheme.outlineVariant.withValues(alpha: 0.5),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: isLight ? Colors.white : scheme.surfaceContainerHigh,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
      ),
    );
  }
}
