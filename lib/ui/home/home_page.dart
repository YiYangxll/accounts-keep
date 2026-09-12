/// 首页：本月收支概览 + 最近流水 + 数据告警提示。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/date_x.dart';
import '../../core/money.dart';
import '../../data/ledger_repository.dart';
import '../../domain/selectors.dart';
import '../../domain/transaction.dart';
import '../../state/settings_controller.dart';
import '../accounts/accounts_page.dart';
import '../common/transaction_tile.dart';
import '../common/widgets.dart';
import '../entry/transaction_editor_page.dart';
import '../theme/app_theme.dart';

/// 首页。
class HomePage extends StatelessWidget {
  /// 构造。
  const HomePage({super.key, this.now});

  /// 时钟，便于测试注入固定的「本月」。
  ///
  /// 首页概览只统计「本月」，若直接用 `DateTime.now()`，测试就无法在不依赖
  /// 真实系统时间的前提下断言本月合计（跨月运行时结论还会变）。生产环境不传。
  final DateTime Function()? now;

  /// 概览卡片上「净资产」金额的定位键。
  ///
  /// 同一个金额文本在首页会合法地出现多次（净资产、本月收入/支出/结余、
  /// 以及最近流水里的那一条），只按文本断言必然歧义，因此给这几个展示位
  /// 固定 key，供测试与无障碍定位使用。
  static const Key netWorthKey = Key('home-net-worth');

  /// 「本月收入」金额的定位键。
  static const Key monthIncomeKey = Key('home-month-income');

  /// 「本月支出」金额的定位键。
  static const Key monthExpenseKey = Key('home-month-expense');

  /// 「结余」金额的定位键。
  static const Key monthNetKey = Key('home-month-net');

  @override
  Widget build(BuildContext context) {
    final LedgerRepository repository = context.watch<LedgerRepository>();
    final SettingsController settings = context.watch<SettingsController>();
    final List<Transaction> active =
        Selectors.active(repository.data.transactions);
    // 首页概览固定看「本月」，历史数据请到账单页按区间查看。
    final MonthKey thisMonth = MonthKey.of((now ?? DateTime.now)());
    final PeriodSummary summary =
        Selectors.summarize(Selectors.inMonth(active, thisMonth));
    final int netWorth = Selectors.netWorth(
      repository.data.accounts,
      repository.data.transactions,
    );
    final List<Transaction> recent =
        Selectors.sortedByTimeDesc(active).take(20).toList();
    final String symbol = settings.currencySymbol;

    return RefreshIndicator(
      onRefresh: () async {
        await repository.load();
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: <Widget>[
          if (repository.lastRead != null &&
              repository.lastRead!.warnings.isNotEmpty)
            NoticeBanner(
              message: repository.lastRead!.warnings.join('\n'),
              onDismiss: repository.acknowledgeWarnings,
            ),
          _NetWorthCard(
            netWorthCents: netWorth,
            incomeCents: summary.incomeCents,
            expenseCents: summary.expenseCents,
            symbol: symbol,
            onTapAccounts: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => const AccountsPage(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: '最近流水',
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: recent.isEmpty
                ? const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: EmptyState(
                      icon: Icons.edit_note_outlined,
                      title: '还没有记账记录',
                      description: '点击右下角「记一笔」，开始记录第一笔收支',
                    ),
                  )
                : Column(
                    children: <Widget>[
                      for (final Transaction t in recent)
                        TransactionTile(
                          transaction: t,
                          showDate: true,
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
      ),
    );
  }
}

class _NetWorthCard extends StatelessWidget {
  const _NetWorthCard({
    required this.netWorthCents,
    required this.incomeCents,
    required this.expenseCents,
    required this.symbol,
    required this.onTapAccounts,
  });

  final int netWorthCents;
  final int incomeCents;
  final int expenseCents;
  final String symbol;
  final VoidCallback onTapAccounts;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int net = incomeCents - expenseCents;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              InkWell(
                onTap: onTapAccounts,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          '净资产',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      Money.format(netWorthCents, symbol: symbol),
                      key: HomePage.netWorthKey,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _AmountColumn(
                      label: '本月收入',
                      text: Money.format(incomeCents, symbol: symbol),
                      valueKey: HomePage.monthIncomeKey,
                      color: AppTheme.incomeColor,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 34,
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                  Expanded(
                    child: _AmountColumn(
                      label: '本月支出',
                      text: Money.format(expenseCents, symbol: symbol),
                      valueKey: HomePage.monthExpenseKey,
                      color: AppTheme.expenseColor,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 34,
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                  Expanded(
                    child: _AmountColumn(
                      label: '结余',
                      text: Money.format(net, symbol: symbol),
                      valueKey: HomePage.monthNetKey,
                      color: AppTheme.amountColor(context, net),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AmountColumn extends StatelessWidget {
  const _AmountColumn({
    required this.label,
    required this.text,
    required this.color,
    this.valueKey,
  });

  final String label;
  final String text;
  final Color color;

  /// 金额文本的定位键（见 [HomePage.netWorthKey] 的说明）。
  final Key? valueKey;

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
            text,
            key: valueKey,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
