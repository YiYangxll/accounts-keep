/// 流水列表项：账单页、首页与账户详情共用。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../data/ledger_repository.dart';
import '../../domain/account.dart';
import '../../domain/category.dart';
import '../../domain/enums.dart';
import '../../domain/transaction.dart';
import '../../state/settings_controller.dart';
import '../theme/app_theme.dart';
import 'format.dart';
import 'icon_map.dart';

/// 单条流水的展示行。
class TransactionTile extends StatelessWidget {
  /// 构造。
  const TransactionTile({
    required this.transaction,
    this.onTap,
    this.onLongPress,
    this.showDate = false,
    super.key,
  });

  /// 流水。
  final Transaction transaction;

  /// 点击回调。
  final VoidCallback? onTap;

  /// 长按回调。
  final VoidCallback? onLongPress;

  /// 是否在副标题中显示日期（首页与筛选结果中需要用）。
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final LedgerRepository repository = context.watch<LedgerRepository>();
    final SettingsController settings = context.watch<SettingsController>();
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final Account? account = repository.data.accountById(transaction.accountId);
    final Account? toAccount = transaction.toAccountId == null
        ? null
        : repository.data.accountById(transaction.toAccountId!);
    final Category? category = transaction.categoryId == null
        ? null
        : repository.data.categoryById(transaction.categoryId!);

    final IconData icon = transaction.kind == TxKind.transfer
        ? Icons.swap_horiz
        : iconForName(category?.iconName);
    final Color iconColor = transaction.kind == TxKind.transfer
        ? AppTheme.transferColor
        : (colorFromHex(category?.colorHex) ?? scheme.primary);

    final String title = transaction.kind == TxKind.transfer
        ? '${account?.name ?? '未知账户'} → ${toAccount?.name ?? '未知账户'}'
        : (category?.name ?? '未分类');

    final List<String> subtitleParts = <String>[
      if (showDate) formatRelativeDay(transaction.wallClock),
      if (transaction.kind != TxKind.transfer) account?.name ?? '未知账户',
      if (transaction.payee != null && transaction.payee!.isNotEmpty)
        transaction.payee!,
      if (transaction.note != null && transaction.note!.isNotEmpty)
        transaction.note!,
    ];

    final int signedAmount = transaction.kind == TxKind.income
        ? transaction.amountCents
        : -transaction.amountCents;
    final String amountText = transaction.kind == TxKind.transfer
        ? Money.format(transaction.amountCents, symbol: settings.currencySymbol)
        : formatSignedMoney(
            signedAmount,
            symbol: settings.currencySymbol,
          );
    final Color amountColor = transaction.kind == TxKind.transfer
        ? scheme.onSurface
        : (transaction.kind == TxKind.income
            ? AppTheme.incomeColor
            : AppTheme.expenseColor);

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: CircleAvatar(
        backgroundColor: iconColor.withValues(alpha: 0.14),
        child: Icon(icon, size: 20, color: iconColor),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: subtitleParts.isEmpty
          ? null
          : Text(
              subtitleParts.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            amountText,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: amountColor,
              decoration:
                  transaction.isDeleted ? TextDecoration.lineThrough : null,
            ),
          ),
          if (transaction.kind == TxKind.transfer && transaction.feeCents > 0)
            Text(
              '手续费 ${Money.format(transaction.feeCents, symbol: settings.currencySymbol)}',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}
