/// 记一笔 / 编辑流水页面。
library;

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/date_x.dart';
import '../../core/money.dart';
import '../../core/result.dart';
import '../../data/ledger_repository.dart';
import '../../domain/account.dart';
import '../../domain/category.dart';
import '../../domain/enums.dart';
import '../../domain/transaction.dart';
import '../../state/settings_controller.dart';
import '../common/icon_map.dart';
import '../common/widgets.dart';

/// 交易编辑页面。
class TransactionEditorPage extends StatefulWidget {
  /// 构造。
  const TransactionEditorPage({
    this.existing,
    this.initialKind,
    this.clock,
    super.key,
  });

  /// 路由名（供 onGenerateRoute 使用）。
  static const String routeName = '/entry';

  /// 要编辑的流水；为空表示新建。
  final Transaction? existing;

  /// 新建时的初始类型。
  final TxKind? initialKind;

  /// 时钟，便于测试注入固定时间。
  final DateTime Function()? clock;

  @override
  State<TransactionEditorPage> createState() => _TransactionEditorPageState();
}

class _TransactionEditorPageState extends State<TransactionEditorPage> {
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  late final TextEditingController _payeeController;
  late final TextEditingController _feeController;

  late TxKind _kind;
  late DateTime _occurredAt;
  String? _accountId;
  String? _toAccountId;
  String? _categoryId;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final Transaction? existing = widget.existing;
    _amountController = TextEditingController(
      text: existing == null ? '' : Money.toPlainString(existing.amountCents),
    );
    _noteController = TextEditingController(text: existing?.note ?? '');
    _payeeController = TextEditingController(text: existing?.payee ?? '');
    _feeController = TextEditingController(
      text: (existing?.feeCents ?? 0) == 0
          ? ''
          : Money.toPlainString(existing!.feeCents),
    );
    _kind = existing?.kind ?? widget.initialKind ?? TxKind.expense;
    _occurredAt = existing?.wallClock ?? _now();
    _accountId = existing?.accountId;
    _toAccountId = existing?.toAccountId;
    _categoryId = existing?.categoryId;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _payeeController.dispose();
    _feeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LedgerRepository repository = context.watch<LedgerRepository>();
    final SettingsController settings = context.watch<SettingsController>();
    final List<Account> accounts = repository.data.activeAccounts;
    final List<Category> categories = repository.data.activeCategories
        .where((Category c) => c.kind.asTxKind == _kind)
        .toList()
      ..sort((Category a, Category b) => a.sortOrder.compareTo(b.sortOrder));

    // 新建时给出合理的默认账户，避免用户每次都要选择。
    _accountId ??= accounts.isEmpty ? null : accounts.first.id;
    if (_kind == TxKind.transfer) {
      _toAccountId ??= accounts
          .where((Account a) => a.id != _accountId)
          .map((Account a) => a.id)
          .firstOrNull;
    }

    return Scaffold(
      // 表单较长，键盘弹起时把可视区收缩，让 ListView 能滚动到当前输入框，
      // 避免下方的账户/日期等控件被键盘盖住。
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(_isEditing ? '编辑流水' : '记一笔'),
        actions: <Widget>[
          if (_isEditing)
            IconButton(
              tooltip: '删除',
              onPressed: _saving ? null : () => _delete(repository),
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: accounts.isEmpty
          ? const EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: '请先创建一个账户',
              description: '账户用于记录资金的来源与去向，可在「我的 → 账户管理」中添加',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: <Widget>[
                SegmentedButton<TxKind>(
                  segments: const <ButtonSegment<TxKind>>[
                    ButtonSegment<TxKind>(
                      value: TxKind.expense,
                      label: Text('支出'),
                      icon: Icon(Icons.remove_circle_outline),
                    ),
                    ButtonSegment<TxKind>(
                      value: TxKind.income,
                      label: Text('收入'),
                      icon: Icon(Icons.add_circle_outline),
                    ),
                    ButtonSegment<TxKind>(
                      value: TxKind.transfer,
                      label: Text('转账'),
                      icon: Icon(Icons.swap_horiz),
                    ),
                  ],
                  selected: <TxKind>{_kind},
                  onSelectionChanged: (Set<TxKind> selection) {
                    setState(() {
                      _kind = selection.first;
                      if (_kind == TxKind.transfer) {
                        _categoryId = null;
                      } else if (_categoryId != null) {
                        final Category? current =
                            repository.data.categoryById(_categoryId!);
                        if (current == null || current.kind.asTxKind != _kind) {
                          _categoryId = null;
                        }
                      }
                    });
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _amountController,
                  autofocus: !_isEditing,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  // 金额字号远大于正文，需要比主题默认更多的垂直内边距，
                  // 否则标签「金额」、输入的数字与光标会显得挤在一起。
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                  scrollPadding: const EdgeInsets.only(bottom: 200),
                  decoration: InputDecoration(
                    prefixText: '${settings.currencySymbol} ',
                    prefixStyle: const TextStyle(fontSize: 24),
                    labelText: '金额',
                    hintText: '0.00',
                    errorText: _amountError,
                    // 金额框保留 0.00 占位提示，因此不强制常驻上浮；
                    // 它本身只有 1 行、上下没有紧邻的输入框，不会出现标签粘连。
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 20,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                if (_kind != TxKind.transfer) ...<Widget>[
                  Text(
                    '分类',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  if (categories.isEmpty)
                    Text(
                      '暂无可用分类，请在「我的 → 分类管理」中添加',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final Category c in categories)
                          ChoiceChip(
                            selected: _categoryId == c.id,
                            onSelected: (_) =>
                                setState(() => _categoryId = c.id),
                            avatar: Icon(
                              iconForName(c.iconName),
                              size: 18,
                              color: colorFromHex(c.colorHex),
                            ),
                            label: Text(c.name),
                          ),
                      ],
                    ),
                  const SizedBox(height: 16),
                ],
                _AccountPicker(
                  label: _kind == TxKind.transfer ? '转出账户' : '账户',
                  accounts: accounts,
                  value: _accountId,
                  onChanged: (String? value) => setState(() {
                    _accountId = value;
                    if (_toAccountId == value) {
                      _toAccountId = null;
                    }
                    if (_kind == TxKind.transfer && _toAccountId == null) {
                      _toAccountId = accounts
                          .where((Account a) => a.id != value)
                          .map((Account a) => a.id)
                          .firstOrNull;
                    }
                  }),
                ),
                if (_kind == TxKind.transfer) ...<Widget>[
                  const SizedBox(height: 12),
                  _AccountPicker(
                    label: '转入账户',
                    accounts: accounts
                        .where((Account a) => a.id != _accountId)
                        .toList(),
                    value: _toAccountId,
                    onChanged: (String? value) =>
                        setState(() => _toAccountId = value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _feeController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    scrollPadding: const EdgeInsets.only(bottom: 200),
                    decoration: InputDecoration(
                      labelText: '手续费（可选）',
                      prefixText: '${settings.currencySymbol} ',
                      errorText: _feeError,
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '日期',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.event_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_occurredAt.dateText} '
                            '${_occurredAt.hour.toString().padLeft(2, '0')}:'
                            '${_occurredAt.minute.toString().padLeft(2, '0')}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _payeeController,
                  decoration: const InputDecoration(
                    labelText: '交易对象（可选）',
                    // 标签常驻上浮，位置不随焦点/内容变化，避免空框时标签落在框内
                    // 偏下位置、与相邻的日期框视觉粘连。
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '备注（可选）',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : () => _save(repository),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(_saving ? '保存中…' : '保存'),
                ),
              ],
            ),
    );
  }

  String? get _amountError {
    final String text = _amountController.text.trim();
    if (text.isEmpty) {
      return null;
    }
    final int? cents = Money.tryParseUnitsToCents(text);
    if (cents == null) {
      return '请输入合法金额';
    }
    if (cents <= 0) {
      return '金额必须大于 0';
    }
    if (cents > Money.maxCents) {
      return '金额不能超过 1 亿元';
    }
    return null;
  }

  String? get _feeError {
    final String text = _feeController.text.trim();
    if (text.isEmpty) {
      return null;
    }
    final int? cents = Money.tryParseUnitsToCents(text);
    if (cents == null) {
      return '请输入合法金额';
    }
    return null;
  }

  Future<void> _pickDate() async {
    final DateTime now = _now();
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 5, 12, 31),
      locale: const Locale('zh', 'CN'),
    );
    if (date == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _occurredAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _occurredAt.hour,
        time?.minute ?? _occurredAt.minute,
      );
    });
  }

  Future<void> _save(LedgerRepository repository) async {
    final int? cents = Money.tryParseUnitsToCents(_amountController.text);
    if (cents == null || cents <= 0) {
      showAppSnackBar(context, '请输入大于 0 的金额');
      return;
    }
    if (_kind != TxKind.transfer && _categoryId == null) {
      showAppSnackBar(context, '请选择分类');
      return;
    }
    final String? accountId = _accountId;
    if (accountId == null) {
      showAppSnackBar(context, '请选择账户');
      return;
    }
    if (_kind == TxKind.transfer) {
      final String? to = _toAccountId;
      if (to == null) {
        showAppSnackBar(context, '请选择转入账户');
        return;
      }
      if (to == accountId) {
        showAppSnackBar(context, '转出与转入账户不能是同一个账户');
        return;
      }
    }
    final int feeCents = _kind == TxKind.transfer
        ? (Money.tryParseUnitsToCents(_feeController.text) ?? 0)
        : 0;

    final DateTime now = _now();
    final Transaction draft = Transaction(
      id: widget.existing?.id ?? 'tx_${const Uuid().v4()}',
      kind: _kind,
      amountCents: cents,
      accountId: accountId,
      toAccountId: _kind == TxKind.transfer ? _toAccountId : null,
      feeCents: feeCents,
      categoryId: _kind == TxKind.transfer ? null : _categoryId,
      occurredAtUtc: _occurredAt.toUtc(),
      utcOffsetMinutes: _occurredAt.timeZoneOffset.inMinutes,
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      payee: _payeeController.text.trim().isEmpty
          ? null
          : _payeeController.text.trim(),
      createdAtUtc: widget.existing?.createdAtUtc ?? now.toUtc(),
      updatedAtUtc: now.toUtc(),
    );

    setState(() => _saving = true);
    final Result<Transaction> result = widget.existing == null
        ? await repository.addTransaction(draft)
        : await repository.updateTransaction(draft);
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    if (result.isErr) {
      showAppSnackBar(context, result.error!.message);
      return;
    }
    final String message = widget.existing == null ? '已记账' : '已更新';
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
    showAppSnackBar(context, message);
  }

  Future<void> _delete(LedgerRepository repository) async {
    final String id = widget.existing!.id;
    final bool confirmed = await confirmDialog(
      context,
      title: '删除这笔流水？',
      message: '删除后可用「撤销」恢复。',
      confirmText: '删除',
      destructive: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    final Result<Unit> result = await repository.deleteTransaction(id);
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
      '已删除',
      action: SnackBarAction(
        label: '撤销',
        onPressed: () => unawaited(repository.restoreTransaction(id)),
      ),
    );
  }
}

class _AccountPicker extends StatelessWidget {
  const _AccountPicker({
    required this.label,
    required this.accounts,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<Account> accounts;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: accounts.any((Account a) => a.id == value) ? value : null,
      // 标签常驻上浮，与其它输入框的标签位置保持一致（否则账户行的标签会
      // 落在框内偏下位置，视觉上与相邻的日期行粘连）。
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
      items: <DropdownMenuItem<String>>[
        for (final Account a in accounts)
          DropdownMenuItem<String>(
            value: a.id,
            child: Row(
              children: <Widget>[
                Icon(iconForName(a.iconName), size: 18),
                const SizedBox(width: 8),
                Text(a.name),
              ],
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
