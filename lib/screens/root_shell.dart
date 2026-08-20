import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../recurring.dart';
import '../store.dart';
import 'budgets_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'transactions_screen.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // The recurring check runs exactly once, at launch. No timers, no polling.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.read<AppStore>().dueRules().isEmpty) return;
      showDueRulesDialog(context);
    });
  }

  void _go(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = <Widget>[
      HomeScreen(
        onOpenBudgets: () => _go(2),
        onOpenTransactions: () => _go(1),
      ),
      const TransactionsScreen(),
      const BudgetsScreen(),
      const SettingsScreen(),
    ];

    // Phone APK uses a bottom bar. Linux/Windows keep the side rail — a
    // narrow desktop window does not switch layouts.
    if (kIsMobile) {
      return Scaffold(
        body: SafeArea(bottom: false, child: pages[_index]),
        bottomNavigationBar: ColoredBox(
          color: kSurface,
          child: SafeArea(
            top: false,
            child: NavigationBar(
              backgroundColor: kSurface,
              indicatorColor: kAccentFaint,
              selectedIndex: _index,
              onDestinationSelected: _go,
              destinations: const <Widget>[
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: 'History',
                ),
                NavigationDestination(
                  icon: Icon(Icons.pie_chart_outline),
                  selectedIcon: Icon(Icons.pie_chart),
                  label: 'Budgets',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: <Widget>[
          NavigationRail(
            backgroundColor: kSurface,
            selectedIndex: _index,
            onDestinationSelected: _go,
            labelType: NavigationRailLabelType.all,
            indicatorColor: kAccentFaint,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Icon(Icons.account_balance_wallet, color: kAccent),
            ),
            destinations: const <NavigationRailDestination>[
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('Home'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: Text('History'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.pie_chart_outline),
                selectedIcon: Icon(Icons.pie_chart),
                label: Text('Budgets'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(width: 1, thickness: 1, color: kBorder),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: pages[_index],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
