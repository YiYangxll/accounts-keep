/// 账单筛选面板。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/date_x.dart';
import '../../data/ledger_repository.dart';
import '../../domain/account.dart';
import '../../domain/category.dart';
import '../../domain/enums.dart';
import '../../domain/transaction_filter.dart';
import '../common/icon_map.dart';

/// 弹出筛选面板，返回用户确认后的筛选条件；取消则返回 null。
Future<TransactionFilter?> showFilterSheet(
  BuildContext context,
  TransactionFilter current, {
  DateTime? now,
}) {
  return showModalBottomSheet<TransactionFilter>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => _FilterSheet(
      initial: current,
      now: now,
    ),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial, this.now});

  final TransactionFilter initial;
  final DateTime? now;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late TransactionFilter _draft;
  late final TextEditingController _keywordController;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
    _keywordController = TextEditingController(text: widget.initial.keyword);
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LedgerRepository repository = context.watch<LedgerRepository>();
    final List<Account> accounts = repository.data.activeAccounts;
    final List<Category> categories = repository.data.activeCategories
      ..sort((Category a, Category b) => a.sortOrder.compareTo(b.sortOrder));
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text('筛选', style: theme.textTheme.titleMedium),
                ),
                TextButton(
                  onPressed: () => setState(() => _draft = _draft.cleared()),
                  child: const Text('重置'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('时间范围', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final DateRangePreset preset in DateRangePreset.values
                    .where((DateRangePreset p) => p != DateRangePreset.custom))
                  ChoiceChip(
                    label: Text(preset.label),
                    selected: _draft.preset == preset,
                    onSelected: (_) => setState(
                      () => _draft = _draft.copyWith(preset: preset),
                    ),
                  ),
                ChoiceChip(
                  // 这颗 chip 代表「自定义」，与上面的预设是并列关系，
                  // 因此无论当前预设是什么，未选区间时都应显示「自定义」
                  // （不能借用 _draft.preset.label：那是「本月」）。
                  label: Text(
                    DateRangePreset.custom.labelWith(
                      start: _draft.customStart,
                      endExclusive: _draft.customEndExclusive,
                    ),
                  ),
                  selected: _draft.preset == DateRangePreset.custom,
                  onSelected: (_) => _pickCustomRange(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('类型', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final TxKind kind in TxKind.values)
                  FilterChip(
                    label: Text(kind.label),
                    selected: _draft.kinds.contains(kind),
                    onSelected: (bool selected) {
                      final Set<TxKind> next = <TxKind>{..._draft.kinds};
                      if (selected) {
                        next.add(kind);
                      } else {
                        next.remove(kind);
                      }
                      setState(() => _draft = _draft.copyWith(kinds: next));
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('账户', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final Account account in accounts)
                  FilterChip(
                    avatar: Icon(iconForName(account.iconName), size: 16),
                    label: Text(account.name),
                    selected: _draft.accountIds.contains(account.id),
                    onSelected: (bool selected) {
                      final Set<String> next = <String>{..._draft.accountIds};
                      if (selected) {
                        next.add(account.id);
                      } else {
                        next.remove(account.id);
                      }
                      setState(
                        () => _draft = _draft.copyWith(accountIds: next),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('分类', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final Category category in categories)
                  FilterChip(
                    avatar: Icon(iconForName(category.iconName), size: 16),
                    label: Text(
                      '${category.kind == CategoryKind.expense ? '支出' : '收入'}·${category.name}',
                    ),
                    selected: _draft.categoryIds.contains(category.id),
                    onSelected: (bool selected) {
                      final Set<String> next = <String>{..._draft.categoryIds};
                      if (selected) {
                        next.add(category.id);
                      } else {
                        next.remove(category.id);
                      }
                      setState(
                        () => _draft = _draft.copyWith(categoryIds: next),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _keywordController,
              decoration: InputDecoration(
                labelText: '关键词',
                hintText: '备注、交易对象或金额',
                suffixIcon: _keywordController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _keywordController.clear();
                          setState(
                            () => _draft = _draft.copyWith(keyword: ''),
                          );
                        },
                      ),
              ),
              onChanged: (String value) =>
                  setState(() => _draft = _draft.copyWith(keyword: value)),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _draft.includeDeleted,
              onChanged: (bool value) => setState(
                  () => _draft = _draft.copyWith(includeDeleted: value)),
              title: const Text('包含已删除的记录'),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(_draft),
                    child: const Text('应用'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCustomRange() async {
    final DateTime now = widget.now ?? DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 5, 12, 31),
      initialDateRange: _draft.customStart != null &&
              _draft.customEndExclusive != null
          ? DateTimeRange(
              start: _draft.customStart!,
              end: _draft.customEndExclusive!.subtract(const Duration(days: 1)),
            )
          : null,
      locale: const Locale('zh', 'CN'),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _draft = _draft.copyWith(
        preset: DateRangePreset.custom,
        customStart: picked.start.startOfDay,
        customEndExclusive: picked.end.startOfDay.add(const Duration(days: 1)),
      );
    });
  }
}
