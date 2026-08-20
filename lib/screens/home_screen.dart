import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models.dart';
import '../store.dart';
import '../widgets/common.dart';
import 'transaction_edit_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.onOpenBudgets,
    required this.onOpenTransactions,
  });

  final VoidCallback onOpenBudgets;
  final VoidCallback onOpenTransactions;

  @override
  Widget build(BuildContext context) {
    final AppStore store = context.watch<AppStore>();

    return ListView(
      padding: pagePadding(),
      children: <Widget>[
        if (kIsMobile) ...<Widget>[
          const Text(
            'Dashboard',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const MonthSwitcher(),
        ] else
          const Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Dashboard',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ),
              MonthSwitcher(),
            ],
          ),
        const SizedBox(height: 18),
        _BalancePanel(store: store),
        const SizedBox(height: 14),
        if (store.people.any((PersonBalance p) => p.net != 0)) ...<Widget>[
          _IouPanel(store: store),
          const SizedBox(height: 14),
        ],
        _MonthPanel(store: store, onOpenBudgets: onOpenBudgets),
        const SizedBox(height: 18),
        SizedBox(
          height: 56,
          child: FilledButton.icon(
            onPressed: () => openTransactionEditor(context),
            icon: const Icon(Icons.add, size: 22),
            label: const Text(
              'Add transaction',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        if (store.presets.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: store.presets
                .map(
                  (Preset preset) => ActionChip(
                    avatar: const Icon(Icons.bolt, size: 15, color: kAccent),
                    backgroundColor: kSurface,
                    side: const BorderSide(color: kBorder),
                    label: Text(
                      '${preset.label} · ${amountFieldText(preset.amount)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () =>
                        openTransactionEditor(context, preset: preset),
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 20),
        Panel(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PanelTitle(
                'Recent',
                trailing: TextButton(
                  onPressed: onOpenTransactions,
                  child: const Text('View all'),
                ),
              ),
              if (store.recent.isEmpty)
                const EmptyHint('No transactions yet. Add your first one above.')
              else
                ...store.recent.map(
                  (Txn txn) => TxnTile(
                    txn: txn,
                    onTap: () => openTransactionEditor(context, existing: txn),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BalancePanel extends StatefulWidget {
  const _BalancePanel({required this.store});

  final AppStore store;

  @override
  State<_BalancePanel> createState() => _BalancePanelState();
}

class _BalancePanelState extends State<_BalancePanel> {
  /// Home stays on cash. Swipe left to see cash + bank as a total.
  bool _showTotal = false;

  bool _isCash(Account account) =>
      account.name.trim().toLowerCase() == 'cash';

  Widget _accountLine(String name, double amount) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                name,
                style: const TextStyle(color: kTextMuted, fontSize: 13),
              ),
            ),
            Text(
              formatMoney(amount),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final AppStore store = widget.store;
    final List<Account> cashNamed =
        store.accounts.where(_isCash).toList();
    final Account? pocket;
    final List<Account> bank;
    if (cashNamed.isNotEmpty) {
      pocket = cashNamed.first;
      bank = store.accounts.where((Account a) => !_isCash(a)).toList();
    } else if (store.accounts.isNotEmpty) {
      pocket = store.accounts.first;
      bank = store.accounts.skip(1).toList();
    } else {
      pocket = null;
      bank = const <Account>[];
    }
    final double cashAmount = pocket?.currentBalance ?? 0;

    return GestureDetector(
      onHorizontalDragEnd: (DragEndDetails details) {
        final double v = details.primaryVelocity ?? 0;
        if (bank.isEmpty) return;
        if (v < -200) setState(() => _showTotal = true);
        if (v > 200) setState(() => _showTotal = false);
      },
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            PanelTitle(_showTotal ? 'Total balance' : 'Cash'),
            const SizedBox(height: 6),
            Text(
              formatMoney(_showTotal ? store.totalBalance : cashAmount),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: (_showTotal ? store.totalBalance : cashAmount) < 0
                    ? kExpense
                    : kText,
              ),
            ),
            if (_showTotal) ...<Widget>[
              const SizedBox(height: 12),
              if (pocket != null) _accountLine(pocket.name, cashAmount),
              ...bank.map(
                (Account account) =>
                    _accountLine(account.name, account.currentBalance),
              ),
              const Text(
                'Swipe right to show cash only.',
                style: TextStyle(color: kTextMuted, fontSize: 11),
              ),
            ] else if (bank.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'Swipe left for total (cash + bank).',
                  style: TextStyle(color: kTextMuted, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MonthPanel extends StatelessWidget {
  const _MonthPanel({required this.store, required this.onOpenBudgets});

  final AppStore store;
  final VoidCallback onOpenBudgets;

  @override
  Widget build(BuildContext context) {
    final double? limit = store.overallLimit;
    final double spent = store.monthExpense;
    final double ratio = (limit == null || limit <= 0) ? 0 : spent / limit;
    final bool over = limit != null && spent > limit;

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          PanelTitle(
            '${formatMonth(store.month)} · spend vs budget',
            trailing: TextButton(
              onPressed: onOpenBudgets,
              child: Text(limit == null ? 'Set budget' : 'Edit'),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                formatMoney(spent),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: over ? kExpense : kText,
                ),
              ),
              if (limit != null)
                Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 3),
                  child: Text(
                    'of ${formatMoney(limit)}',
                    style: const TextStyle(color: kTextMuted, fontSize: 13),
                  ),
                ),
              const Spacer(),
              Text(
                'Income ${formatMoney(store.monthIncome)}',
                style: const TextStyle(color: kTextMuted, fontSize: 12),
              ),
            ],
          ),
          if (store.monthLent > 0 || store.monthBorrowed > 0) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              [
                if (store.monthLent > 0)
                  'Lent ${formatMoney(store.monthLent)}',
                if (store.monthBorrowed > 0)
                  'Borrowed ${formatMoney(store.monthBorrowed)}',
              ].join('  ·  '),
              style: const TextStyle(color: kTextMuted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          if (limit == null)
            const Text(
              'No overall monthly limit set yet.',
              style: TextStyle(color: kTextMuted, fontSize: 12),
            )
          else ...<Widget>[
            ProgressBar(value: ratio, color: over ? kExpense : kAccent),
            const SizedBox(height: 6),
            Text(
              over
                  ? '${formatMoney(spent - limit)} over budget'
                  : '${formatMoney(limit - spent)} left · ${(ratio * 100).round()}% used',
              style: TextStyle(
                color: over ? kExpense : kTextMuted,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _IouPanel extends StatelessWidget {
  const _IouPanel({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final List<PersonBalance> open = store.people
        .where((PersonBalance p) => p.net != 0)
        .toList();
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const PanelTitle('Lend & borrow'),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _IouStat(
                  label: 'Owed to you',
                  value: store.owedToYou,
                  color: kLend,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _IouStat(
                  label: 'You owe',
                  value: store.youOwe,
                  color: kBorrow,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...open.map(
            (PersonBalance person) {
              final bool theyOwe = person.net > 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: <Widget>[
                    Icon(
                      theyOwe ? Icons.call_made : Icons.call_received,
                      size: 16,
                      color: theyOwe ? kLend : kBorrow,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        person.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      theyOwe
                          ? 'owes you ${formatMoney(person.net)}'
                          : 'you owe ${formatMoney(-person.net)}',
                      style: TextStyle(
                        color: theyOwe ? kLend : kBorrow,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _IouStat extends StatelessWidget {
  const _IouStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: const TextStyle(color: kTextMuted, fontSize: 11)),
          const SizedBox(height: 2),
          Text(
            formatMoney(value),
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
}
