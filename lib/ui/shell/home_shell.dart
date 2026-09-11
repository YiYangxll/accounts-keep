/// 应用主框架：底部导航 + 记账入口。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/ledger_repository.dart';
import '../../domain/enums.dart';
import '../accounts/accounts_page.dart';
import '../bills/bill_list_page.dart';
import '../entry/transaction_editor_page.dart';
import '../home/home_page.dart';
import '../settings/settings_page.dart';
import '../stats/stats_page.dart';

/// 主框架页面。
class HomeShell extends StatefulWidget {
  /// 构造。
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const List<String> _titles = <String>['记账本', '账单', '统计', '我的'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: <Widget>[
          if (_index == 0)
            IconButton(
              tooltip: '账户',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => const AccountsPage(),
                ),
              ),
              icon: const Icon(Icons.account_balance_wallet_outlined),
            ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const <Widget>[
          HomePage(),
          BillListPage(),
          StatsPage(),
          SettingsPage(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(TxKind.expense),
        icon: const Icon(Icons.add),
        label: const Text('记一笔'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int value) => setState(() => _index = value),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: '记账',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: '账单',
          ),
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline),
            selectedIcon: Icon(Icons.pie_chart),
            label: '统计',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }

  Future<void> _openEditor(TxKind kind) async {
    final LedgerRepository repository = context.read<LedgerRepository>();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            TransactionEditorPage(initialKind: kind),
      ),
    );
    if (!mounted) {
      return;
    }
    // 保存后由仓库通知刷新，这里只需保证底部导航仍在原页。
    assert(repository.isReady);
  }
}
