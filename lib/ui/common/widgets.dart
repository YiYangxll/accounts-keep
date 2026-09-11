/// 通用小组件：空状态、区块卡片、提示条与确认对话框。
library;

import 'package:flutter/material.dart';

/// 空状态占位。
class EmptyState extends StatelessWidget {
  /// 构造。
  const EmptyState({
    required this.icon,
    required this.title,
    this.description,
    this.action,
    super.key,
  });

  /// 图标。
  final IconData icon;

  /// 主文案。
  final String title;

  /// 补充说明。
  final String? description;

  /// 可选的操作按钮。
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 56,
              color: theme.colorScheme.outline.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (description != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                description!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 带标题的区块容器。
class SectionCard extends StatelessWidget {
  /// 构造。
  const SectionCard({
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  /// 标题。
  final String? title;

  /// 标题右侧操作。
  final Widget? trailing;

  /// 内容内边距。
  final EdgeInsetsGeometry padding;

  /// 内容。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (title != null) ...<Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title!,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// 顶部提示条，用于展示数据恢复告警等。
class NoticeBanner extends StatelessWidget {
  /// 构造。
  const NoticeBanner({
    required this.message,
    this.onDismiss,
    this.icon = Icons.info_outline,
    super.key,
  });

  /// 提示文案。
  final String message;

  /// 关闭回调。
  final VoidCallback? onDismiss;

  /// 图标。
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12.5, color: scheme.onErrorContainer),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 16),
              color: scheme.onErrorContainer,
              visualDensity: VisualDensity.compact,
              tooltip: '关闭',
            ),
        ],
      ),
    );
  }
}

/// 弹出底部提示。
void showAppSnackBar(
  BuildContext context,
  String message, {
  SnackBarAction? action,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: action,
        duration: const Duration(seconds: 3),
      ),
    );
}

/// 弹出二次确认对话框，返回用户是否确认。
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = '确定',
  String cancelText = '取消',
  bool destructive = false,
}) async {
  final ColorScheme scheme = Theme.of(context).colorScheme;
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(cancelText),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return result ?? false;
}
