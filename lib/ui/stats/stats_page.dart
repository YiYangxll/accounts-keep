/// 统计页：分类占比、收支趋势与收支对比。
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/date_x.dart';
import '../../core/money.dart';
import '../../data/ledger_repository.dart';
import '../../domain/category.dart';
import '../../domain/enums.dart';
import '../../domain/selectors.dart';
import '../../domain/transaction.dart';
import '../../domain/transaction_filter.dart';
import '../../state/settings_controller.dart';
import '../common/icon_map.dart';
import '../common/widgets.dart';
import '../theme/app_theme.dart';

/// 统计页。
class StatsPage extends StatefulWidget {
  /// 构造。
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  DateRangePreset _preset = DateRangePreset.thisMonth;
  TxKind _kind = TxKind.expense;

  @override
  Widget build(BuildContext context) {
    final LedgerRepository repository = context.watch<LedgerRepository>();
    final SettingsController settings = context.watch<SettingsController>();
    final String symbol = settings.currencySymbol;
    final DateTime now = DateTime.now();

    final TransactionFilter filter =
        TransactionFilter(preset: _preset, kinds: <TxKind>{_kind});
    final List<Transaction> matched =
        filter.apply(repository.data.transactions, now: now);
    final List<Transaction> active =
        Selectors.active(repository.data.transactions);

    final List<CategoryShare> shares = Selectors.withShares(
      Selectors.totalsByCategory(
        matched,
        kind: _kind,
        categories: repository.data.categories,
      ),
    );
    final PeriodSummary summary = Selectors.summarize(matched);
    final MonthKey currentMonth = MonthKey.of(now);
    final List<PeriodSummary> trend =
        Selectors.monthlyTrend(active, currentMonth, 12);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: <Widget>[
        Center(
          child: SegmentedButton<DateRangePreset>(
            segments: const <ButtonSegment<DateRangePreset>>[
              ButtonSegment<DateRangePreset>(
                value: DateRangePreset.thisMonth,
                label: Text('本月'),
              ),
              ButtonSegment<DateRangePreset>(
                value: DateRangePreset.lastMonth,
                label: Text('上月'),
              ),
              ButtonSegment<DateRangePreset>(
                value: DateRangePreset.lastThreeMonths,
                label: Text('近三月'),
              ),
              ButtonSegment<DateRangePreset>(
                value: DateRangePreset.lastTwelveMonths,
                label: Text('近一年'),
              ),
            ],
            selected: <DateRangePreset>{_preset},
            onSelectionChanged: (Set<DateRangePreset> value) =>
                setState(() => _preset = value.first),
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '分类占比',
          trailing: SegmentedButton<TxKind>(
            showSelectedIcon: false,
            segments: const <ButtonSegment<TxKind>>[
              ButtonSegment<TxKind>(value: TxKind.expense, label: Text('支出')),
              ButtonSegment<TxKind>(value: TxKind.income, label: Text('收入')),
            ],
            selected: <TxKind>{_kind},
            onSelectionChanged: (Set<TxKind> value) =>
                setState(() => _kind = value.first),
          ),
          child: shares.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: EmptyState(
                    icon: Icons.pie_chart_outline,
                    title: '该时间段暂无数据',
                    description: '换一个时间段，或先记几笔账',
                  ),
                )
              : Column(
                  children: <Widget>[
                    SizedBox(
                      height: 200,
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 52,
                          sections: <PieChartSectionData>[
                            for (int i = 0; i < shares.length; i++)
                              PieChartSectionData(
                                value: shares[i].total.amountCents.toDouble(),
                                color: _sliceColor(context, i),
                                radius: 42,
                                showTitle: shares[i].share >= 0.08,
                                title: '${(shares[i].share * 100).round()}%',
                                titleStyle: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (int i = 0; i < shares.length; i++)
                      _CategoryShareRow(
                        share: shares[i],
                        color: _sliceColor(context, i),
                        symbol: symbol,
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '收支对比',
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: _Metric(
                      label: '收入',
                      value: Money.format(summary.incomeCents, symbol: symbol),
                      color: AppTheme.incomeColor,
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      label: '支出',
                      value: Money.format(summary.expenseCents, symbol: symbol),
                      color: AppTheme.expenseColor,
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      label: '结余',
                      value: Money.format(summary.netCents, symbol: symbol),
                      color: AppTheme.amountColor(context, summary.netCents),
                    ),
                  ),
                ],
              ),
              const Divider(height: 28),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _Metric(
                      label: '日均支出',
                      value: Money.format(_dailyAverage(summary.expenseCents),
                          symbol: symbol),
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      label: '笔数',
                      value: '${summary.transactionCount}',
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      label: '单笔最高',
                      value: Money.format(_maxAmount(matched), symbol: symbol),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '近 12 个月趋势',
          child: SizedBox(
            height: 220,
            child: _TrendChart(
              trend: trend,
              endMonth: currentMonth,
              symbol: symbol,
            ),
          ),
        ),
      ],
    );
  }

  int _dailyAverage(int expenseCents) {
    final LocalDateRange? range =
        TransactionFilter(preset: _preset).resolveRange();
    if (range == null) {
      return expenseCents;
    }
    final int days = range.end.difference(range.start).inDays;
    if (days <= 0) {
      return expenseCents;
    }
    return (expenseCents / days).round();
  }

  int _maxAmount(List<Transaction> transactions) {
    int max = 0;
    for (final Transaction t in transactions) {
      if (t.amountCents > max) {
        max = t.amountCents;
      }
    }
    return max;
  }

  Color _sliceColor(BuildContext context, int index) {
    final List<Color> palette = <Color>[
      const Color(0xFF12897A),
      const Color(0xFF2F6FED),
      const Color(0xFFD98C1F),
      const Color(0xFFD93F3F),
      const Color(0xFF7E57C2),
      const Color(0xFF26A69A),
      const Color(0xFFEC407A),
      const Color(0xFF8D6E63),
      const Color(0xFF5C6BC0),
      const Color(0xFF90A4AE),
    ];
    return palette[index % palette.length];
  }
}

class _CategoryShareRow extends StatelessWidget {
  const _CategoryShareRow({
    required this.share,
    required this.color,
    required this.symbol,
  });

  final CategoryShare share;
  final Color color;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Category? category = share.total.category;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Icon(iconForName(category?.iconName), size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              share.total.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          Text(
            '${share.total.transactionCount} 笔',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            share.percentText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            Money.format(share.total.amountCents, symbol: symbol),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: color ?? theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({
    required this.trend,
    required this.endMonth,
    required this.symbol,
  });

  final List<PeriodSummary> trend;
  final MonthKey endMonth;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool hasData = trend.any((PeriodSummary s) => !s.isEmpty);
    if (trend.isEmpty || !hasData) {
      return const EmptyState(
        icon: Icons.bar_chart_outlined,
        title: '暂无趋势数据',
        description: '记录几个月后即可看到收支变化',
      );
    }

    double maxValue = 0;
    for (final PeriodSummary s in trend) {
      final double value = Money.toUnits(
        s.incomeCents > s.expenseCents ? s.incomeCents : s.expenseCents,
      );
      if (value > maxValue) {
        maxValue = value;
      }
    }
    // 顶部留白，并用 1 兜底避免 maxY 为 0。
    final double maxY = (maxValue <= 0 ? 1 : maxValue) * 1.25;
    final MonthKey startMonth = endMonth.shift(-(trend.length - 1));

    return Column(
      children: <Widget>[
        Expanded(
          child: BarChart(
            BarChartData(
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxY / 4,
                getDrawingHorizontalLine: (double value) => FlLine(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.4,
                  ),
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    interval: maxY / 4,
                    getTitlesWidget: (double value, TitleMeta meta) => Text(
                      _compact(value),
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (double value, TitleMeta meta) {
                      final int index = value.round();
                      if (index < 0 || index >= trend.length) {
                        return const SizedBox.shrink();
                      }
                      final MonthKey month = startMonth.shift(index);
                      // 只显示首月、末月与每三个月，避免文字重叠。
                      if (index != 0 &&
                          index != trend.length - 1 &&
                          month.month % 3 != 0) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${month.month}月',
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: <BarChartGroupData>[
                for (int i = 0; i < trend.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 2,
                    barRods: <BarChartRodData>[
                      BarChartRodData(
                        toY: Money.toUnits(trend[i].incomeCents),
                        color: AppTheme.incomeColor,
                        width: 6,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(2),
                        ),
                      ),
                      BarChartRodData(
                        toY: Money.toUnits(trend[i].expenseCents),
                        color: AppTheme.expenseColor,
                        width: 6,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(2),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const _LegendDot(color: AppTheme.incomeColor, label: '收入'),
            const SizedBox(width: 16),
            const _LegendDot(color: AppTheme.expenseColor, label: '支出'),
            const SizedBox(width: 16),
            Text(
              '单位：$symbol',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _compact(double value) {
    if (value >= 10000) {
      return '${(value / 10000).toStringAsFixed(1)}万';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return value.toStringAsFixed(0);
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
