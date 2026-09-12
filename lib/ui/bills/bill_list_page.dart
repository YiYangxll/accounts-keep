/// 账单列表：按月分组、筛选与每日小计。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/date_x.dart';
import '../../core/money.dart';
import '../../data/ledger_repository.dart';
import '../../domain/selectors.dart';
import '../../domain/transaction.dart';
import '../../domain/transaction_filter.dart';
import '../../state/settings_controller.dart';
import '../common/format.dart';
import '../common/transaction_tile.dart';
import '../common/widgets.dart';
import '../entry/transaction_editor_page.dart';
import '../theme/app_theme.dart';
import 'filter_sheet.dart';

/// 账单页。
class BillListPage extends StatefulWidget {
  /// 构造。
  const BillListPage({super.key, this.now});

  /// 时钟，便于测试注入固定的「本月」。
  ///
  /// 「本月 / 上月 / 近三月」这类**相对**时间范围需要知道「今天是哪天」。
  /// 不注入时用系统时间；注入后相对区间与筛选面板共用同一个基准，
  /// 保证测试不受真实系统日期影响（否则跨月运行时结论会变）。生产环境不传。
  final DateTime Function()? now;

  /// 筛选条上「清除」按钮的定位键（仅未处于默认视图时出现）。
  static const Key quickClearKey = Key('bills-quick-clear');

  /// 筛选条上漏斗按钮的定位键。
  static const Key filterButtonKey = Key('bills-filter-button');

  /// 当前时间范围标签的定位键。
  static const Key rangeLabelKey = Key('bills-range-label');

  /// 筛选条件数徽标的定位键。
  static const Key filterBadgeKey = Key('bills-filter-badge');

  @override
  State<BillListPage> createState() => _BillListPageState();
}

class _BillListPageState extends State<BillListPage> {
  TransactionFilter _filter = const TransactionFilter();

  @override
  Widget build(BuildContext context) {
    final LedgerRepository repository = context.watch<LedgerRepository>();
    final SettingsController settings = context.watch<SettingsController>();
    final String symbol = settings.currencySymbol;

    final List<Transaction> matched =
        _filter.apply(repository.data.transactions, now: widget.now?.call());
    final List<Transaction> sorted = Selectors.sortedByTimeDesc(matched);
    final PeriodSummary summary = Selectors.summarize(matched);
    final Map<String, List<Transaction>> byDay = <String, List<Transaction>>{};
    for (final Transaction t in sorted) {
      final String key = t.wallClock.dateText;
      byDay.putIfAbsent(key, () => <Transaction>[]).add(t);
    }

    return Column(
      children: <Widget>[
        _FilterBar(
          filter: _filter,
          onEdit: _openFilter,
          onQuickClear: () => setState(
            () => _filter = _filter.cleared(),
          ),
        ),
        _SummaryStrip(summary: summary, symbol: symbol),
        const Divider(height: 1),
        Expanded(
          child: sorted.isEmpty
              ? EmptyState(
                  icon: Icons.filter_alt_off_outlined,
                  title: '没有符合条件的记录',
                  description: _filter.isUnfiltered
                      ? '点击「记一笔」开始记账'
                      : '试试放宽筛选条件，或点击上方漏斗图标调整',
                  action: _filter.isUnfiltered
                      ? null
                      : OutlinedButton(
                          onPressed: () => setState(
                            () => _filter = _filter.cleared(),
                          ),
                          child: const Text('清除筛选'),
                        ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: byDay.length,
                  itemBuilder: (BuildContext context, int index) {
                    final String day = byDay.keys.elementAt(index);
                    final List<Transaction> items = byDay[day]!;
                    return _DayGroup(
                      day: DateTime.parse(day),
                      transactions: items,
                      symbol: symbol,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _openFilter() async {
    final TransactionFilter? next = await showFilterSheet(
      context,
      _filter,
      now: widget.now?.call(),
    );
    if (next == null || !mounted) {
      return;
    }
    setState(() => _filter = next);
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filter,
    required this.onEdit,
    required this.onQuickClear,
  });

  final TransactionFilter filter;
  final VoidCallback onEdit;
  final VoidCallback onQuickClear;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String rangeText = filter.rangeLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              rangeText,
              key: BillListPage.rangeLabelKey,
              style: theme.textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!filter.isUnfiltered)
            TextButton.icon(
              key: BillListPage.quickClearKey,
              onPressed: onQuickClear,
              icon: const Icon(Icons.close, size: 16),
              label: const Text('清除'),
            ),
          Badge(
            key: BillListPage.filterBadgeKey,
            isLabelVisible: filter.activeFilterCount > 0,
            label: Text('${filter.activeFilterCount}'),
            child: IconButton(
              key: BillListPage.filterButtonKey,
              tooltip: '筛选',
              onPressed: onEdit,
              icon: const Icon(Icons.filter_alt_outlined),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.summary, required this.symbol});

  final PeriodSummary summary;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: <Widget>[
          _Chip(
            label: '收入',
            text: Money.format(summary.incomeCents, symbol: symbol),
            color: AppTheme.incomeColor,
          ),
          const SizedBox(width: 12),
          _Chip(
            label: '支出',
            text: Money.format(summary.expenseCents, symbol: symbol),
            color: AppTheme.expenseColor,
          ),
          const SizedBox(width: 12),
          _Chip(
            label: '结余',
            text: Money.format(summary.netCents, symbol: symbol),
            color: AppTheme.amountColor(context, summary.netCents),
          ),
          const Spacer(),
          Text(
            '${summary.transactionCount} 笔',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.text, required this.color});

  final String label;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          text,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _DayGroup extends StatelessWidget {
  const _DayGroup({
    required this.day,
    required this.transactions,
    required this.symbol,
  });

  final DateTime day;
  final List<Transaction> transactions;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PeriodSummary daySummary = Selectors.summarize(transactions);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.4,
          ),
          child: Row(
            children: <Widget>[
              Text(
                formatRelativeDay(day),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '支 ${Money.format(daySummary.expenseCents, symbol: symbol)}'
                ' · 收 ${Money.format(daySummary.incomeCents, symbol: symbol)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            children: <Widget>[
              for (final Transaction t in transactions)
                TransactionTile(
                  transaction: t,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) =>
                          TransactionEditorPage(existing: t),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
