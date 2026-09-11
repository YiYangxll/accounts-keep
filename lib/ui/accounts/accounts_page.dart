/// 账户管理与余额总览。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../core/result.dart';
import '../../data/ledger_repository.dart';
import '../../domain/account.dart';
import '../../domain/enums.dart';
import '../../domain/selectors.dart';
import '../../state/settings_controller.dart';
import '../common/icon_map.dart';
import '../common/widgets.dart';
import '../theme/app_theme.dart';

/// 账户页。
class AccountsPage extends StatelessWidget {
  /// 构造。
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final LedgerRepository repository = context.watch<LedgerRepository>();
    final SettingsController settings = context.watch<SettingsController>();
    final String symbol = settings.currencySymbol;

    final List<AccountBalance> balances = Selectors.balances(
      repository.data.accounts,
      repository.data.transactions,
    );
    final List<Account> archived =
        repository.data.accounts.where((Account a) => a.isArchived).toList();
    final int assets = Selectors.totalAssets(
      repository.data.accounts,
      repository.data.transactions,
    );
    final int liabilities = Selectors.totalLiabilities(
      repository.data.accounts,
      repository.data.transactions,
    );
    final int net = assets - liabilities;

    return Scaffold(
      appBar: AppBar(title: const Text('账户')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '净资产',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    Money.format(net, symbol: symbol),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Text(
                        '总资产 ${Money.format(assets, symbol: symbol)}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.incomeColor,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '总负债 ${Money.format(liabilities, symbol: symbol)}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.expenseColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Text('我的账户', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _openEditor(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新增账户'),
              ),
            ],
          ),
          if (balances.isEmpty)
            const EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: '还没有账户',
              description: '添加现金、储蓄卡或信用卡等账户，开始记录收支',
            )
          else
            Card(
              child: Column(
                children: <Widget>[
                  for (final AccountBalance balance in balances)
                    _AccountTile(
                      balance: balance,
                      symbol: symbol,
                      onTap: () =>
                          _openEditor(context, existing: balance.account),
                    ),
                ],
              ),
            ),
          if (archived.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            Text('已归档账户', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: <Widget>[
                  for (final Account account in archived)
                    ListTile(
                      leading: Icon(iconForName(account.iconName)),
                      title: Text(account.name),
                      subtitle: const Text('已归档，不计入净资产'),
                      trailing: TextButton(
                        onPressed: () async {
                          final Result<Unit> result =
                              await repository.restoreAccount(account.id);
                          if (!context.mounted) {
                            return;
                          }
                          showAppSnackBar(
                            context,
                            result.isErr ? result.error!.message : '已恢复',
                          );
                        },
                        child: const Text('恢复'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Future<void> _openEditor(
    BuildContext context, {
    Account? existing,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AccountEditorDialog(
        existing: existing,
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.balance,
    required this.symbol,
    required this.onTap,
  });

  final AccountBalance balance;
  final String symbol;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Account account = balance.account;
    final Color color =
        colorFromHex(account.colorHex) ?? theme.colorScheme.primary;
    final String amountText = account.isLiability && balance.balanceCents < 0
        ? '待还款 ${Money.format(balance.debtCents, symbol: symbol)}'
        : Money.format(balance.balanceCents, symbol: symbol);

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.14),
        child: Icon(iconForName(account.iconName), size: 20, color: color),
      ),
      title: Text(account.name),
      subtitle: Text(
        account.kind.label,
        style:
            TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: Text(
        amountText,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: balance.balanceCents < 0
              ? AppTheme.expenseColor
              : theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// 账户新增/编辑对话框。
class AccountEditorDialog extends StatefulWidget {
  /// 构造。
  const AccountEditorDialog({this.existing, super.key});

  /// 要编辑的账户。
  final Account? existing;

  @override
  State<AccountEditorDialog> createState() => _AccountEditorDialogState();
}

class _AccountEditorDialogState extends State<AccountEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _balanceController;
  late AccountKind _kind;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _balanceController = TextEditingController(
      text: widget.existing == null
          ? ''
          : Money.toPlainString(widget.existing!.initialBalanceCents),
    );
    _kind = widget.existing?.kind ?? AccountKind.cash;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LedgerRepository repository = context.read<LedgerRepository>();
    return AlertDialog(
      title: Text(widget.existing == null ? '新增账户' : '编辑账户'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '账户名称',
                hintText: '如：工资卡',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AccountKind>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: '账户类型'),
              items: <DropdownMenuItem<AccountKind>>[
                for (final AccountKind kind in AccountKind.values)
                  DropdownMenuItem<AccountKind>(
                    value: kind,
                    child: Text(kind.label),
                  ),
              ],
              onChanged: (AccountKind? value) {
                if (value != null) {
                  setState(() => _kind = value);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _balanceController,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
              ],
              decoration: const InputDecoration(
                labelText: '期初余额',
                helperText: '信用卡欠款请填负数',
              ),
            ),
            if (widget.existing != null) ...<Widget>[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _saving ? null : () => _delete(repository),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('删除账户'),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : () => _save(repository),
          child: Text(_saving ? '保存中…' : '保存'),
        ),
      ],
    );
  }

  Future<void> _save(LedgerRepository repository) async {
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      showAppSnackBar(context, '请填写账户名称');
      return;
    }
    final int? cents = _balanceController.text.trim().isEmpty
        ? 0
        : _parseSignedAmount(_balanceController.text);
    if (cents == null) {
      showAppSnackBar(context, '期初余额格式不正确');
      return;
    }

    setState(() => _saving = true);
    final Account draft = Account(
      id: widget.existing?.id ?? repository.newId('acc'),
      name: name,
      kind: _kind,
      initialBalanceCents: cents,
      iconName: widget.existing?.iconName ?? _defaultIconName(_kind),
      colorHex: widget.existing?.colorHex ?? _defaultColorHex(_kind),
      sortOrder: widget.existing?.sortOrder ?? 0,
      archivedAt: widget.existing?.archivedAt,
    );
    final Result<Account> result = widget.existing == null
        ? await repository.addAccount(draft)
        : await repository.updateAccount(draft);
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    if (result.isErr) {
      showAppSnackBar(context, result.error!.message);
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _delete(LedgerRepository repository) async {
    final Account account = widget.existing!;
    final int related = repository.data.transactionCountForAccount(account.id);
    if (related == 0) {
      final bool ok = await confirmDialog(
        context,
        title: '删除账户「${account.name}」？',
        message: '该账户没有任何流水，删除后不可恢复。',
        confirmText: '删除',
        destructive: true,
      );
      if (!ok || !mounted) {
        return;
      }
      final Result<Unit> result = await repository.removeAccount(account.id);
      if (!mounted) {
        return;
      }
      if (result.isErr) {
        showAppSnackBar(context, result.error!.message);
        return;
      }
      Navigator.of(context).pop();
      showAppSnackBar(context, '账户已删除');
      return;
    }

    final _DeleteChoice? choice = await showDialog<_DeleteChoice>(
      context: context,
      builder: (BuildContext dialogContext) => _DeleteAccountDialog(
        account: account,
        relatedCount: related,
        candidates: repository.data.accounts
            .where((Account a) => a.id != account.id && !a.isArchived)
            .toList(),
      ),
    );
    if (choice == null || !mounted) {
      return;
    }
    final Result<Unit> result = await repository.deleteAccount(
      account.id,
      strategy: choice.strategy,
      migrateToAccountId: choice.migrateToAccountId,
    );
    if (!mounted) {
      return;
    }
    if (result.isErr) {
      showAppSnackBar(context, result.error!.message);
      return;
    }
    Navigator.of(context).pop();
    showAppSnackBar(
      context,
      choice.strategy == AccountDeletionStrategy.archive
          ? '账户已归档，历史流水保留'
          : '流水已迁移，账户已删除',
    );
  }

  /// 解析可带负号的金额输入。
  static int? _parseSignedAmount(String raw) {
    final String text = raw.trim();
    if (text.startsWith('-')) {
      final int? cents = Money.tryParseUnitsToCents(text.substring(1));
      return cents == null ? null : -cents;
    }
    return Money.tryParseUnitsToCents(text);
  }

  static String _defaultIconName(AccountKind kind) => switch (kind) {
        AccountKind.cash => 'cash',
        AccountKind.debitCard => 'bank',
        AccountKind.alipay => 'alipay',
        AccountKind.wechat => 'wechat',
        AccountKind.creditCard => 'credit_card',
        AccountKind.other => 'more',
      };

  static String _defaultColorHex(AccountKind kind) => switch (kind) {
        AccountKind.cash => '#FF9800',
        AccountKind.debitCard => '#2196F3',
        AccountKind.alipay => '#1677FF',
        AccountKind.wechat => '#07C160',
        AccountKind.creditCard => '#E53935',
        AccountKind.other => '#90A4AE',
      };
}

class _DeleteChoice {
  const _DeleteChoice(this.strategy, this.migrateToAccountId);

  final AccountDeletionStrategy strategy;
  final String? migrateToAccountId;
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({
    required this.account,
    required this.relatedCount,
    required this.candidates,
  });

  final Account account;
  final int relatedCount;
  final List<Account> candidates;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  AccountDeletionStrategy _strategy = AccountDeletionStrategy.archive;
  String? _targetId;

  @override
  void initState() {
    super.initState();
    _targetId = widget.candidates.isEmpty ? null : widget.candidates.first.id;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('删除账户「${widget.account.name}」'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('该账户下还有 ${widget.relatedCount} 条流水，请选择处理方式：'),
          const SizedBox(height: 12),
          ChoiceChip(
            selected: _strategy == AccountDeletionStrategy.archive,
            onSelected: (_) =>
                setState(() => _strategy = AccountDeletionStrategy.archive),
            label: const Text('归档账户，保留流水'),
          ),
          const SizedBox(height: 4),
          const Text(
            '历史记录仍可查询，但不再计入净资产与可选账户。',
            style: TextStyle(fontSize: 12),
          ),
          if (widget.candidates.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            ChoiceChip(
              selected: _strategy == AccountDeletionStrategy.migrate,
              onSelected: (_) =>
                  setState(() => _strategy = AccountDeletionStrategy.migrate),
              label: const Text('迁移流水到其他账户'),
            ),
            const SizedBox(height: 4),
            const Text(
              '该账户下的流水会转移到另一个账户，然后删除本账户。',
              style: TextStyle(fontSize: 12),
            ),
          ],
          if (_strategy == AccountDeletionStrategy.migrate &&
              widget.candidates.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _targetId,
              decoration: const InputDecoration(labelText: '迁移到'),
              items: <DropdownMenuItem<String>>[
                for (final Account a in widget.candidates)
                  DropdownMenuItem<String>(
                    value: a.id,
                    child: Text(a.name),
                  ),
              ],
              onChanged: (String? value) => setState(() => _targetId = value),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _DeleteChoice(_strategy, _targetId),
          ),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
