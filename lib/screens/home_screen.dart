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
        _DailyPanel(store: store),
        const SizedBox(height: 14),
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
                ...store.recent.take(5).map(
                      (Txn txn) => TxnTile(
                        txn: txn,
                        onTap: () =>
                            openTransactionEditor(context, existing: txn),
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DailyPanel extends StatefulWidget {
  const _DailyPanel({required this.store});

  final AppStore store;

  @override
  State<_DailyPanel> createState() => _DailyPanelState();
}

class _DailyPanelState extends State<_DailyPanel> {
  DateTime _day = dayStart(DateTime.now());

  DateTime get _today => dayStart(DateTime.now());

  bool get _isToday => _day == _today;

  void _previousDay() =>
      setState(() => _day = _day.subtract(const Duration(days: 1)));

  void _nextDay() {
    final DateTime next = _day.add(const Duration(days: 1));
    if (next.isAfter(_today)) return;
    setState(() => _day = next);
  }

  @override
  Widget build(BuildContext context) {
    final List<Txn> dayTxns = widget.store.query(from: _day, to: _day);
    final List<Txn> expenses =
        dayTxns.where((Txn txn) => txn.countsAsSpend).toList();
    final double spent = expenses.fold<double>(
      0,
      (double sum, Txn txn) => sum + txn.amount,
    );
    final double income = dayTxns
        .where((Txn txn) => txn.type == TxType.income)
        .fold<double>(0, (double sum, Txn txn) => sum + txn.amount);

    return Panel(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${formatDateHeader(_day)} · spent'.toUpperCase(),
                  style: const TextStyle(
                    color: kTextMuted,
                    fontSize: 11,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Previous day',
                visualDensity: VisualDensity.compact,
                onPressed: _previousDay,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Next day',
                visualDensity: VisualDensity.compact,
                onPressed: _isToday ? null : _nextDay,
                icon: const Icon(Icons.chevron_right),
              ),
              if (!_isToday)
                TextButton(
                  onPressed: () => setState(() => _day = _today),
                  child: const Text('Today'),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  formatMoney(spent),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: spent > 0 ? kExpense : kText,
                  ),
                ),
                const Spacer(),
                if (income > 0)
                  Text(
                    'Income ${formatMoney(income)}',
                    style: const TextStyle(color: kTextMuted, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (expenses.isEmpty)
            const EmptyHint('Nothing spent this day.')
          else
            ...expenses.map(
              (Txn txn) => TxnTile(
                txn: txn,
                onTap: () => openTransactionEditor(context, existing: txn),
              ),
            ),
        ],
      ),
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
    final double cashAmount = pocket?.ownBalance ?? 0;
    final double pocketAmount = pocket?.currentBalance ?? 0;
    final bool showIouTotal = store.owedToYou > 0 || store.youOwe > 0;
    final bool canSwipe = bank.isNotEmpty || showIouTotal;

    return GestureDetector(
      onHorizontalDragEnd: (DragEndDetails details) {
        final double v = details.primaryVelocity ?? 0;
        if (!canSwipe) return;
        if (v < -200) setState(() => _showTotal = true);
        if (v > 200) setState(() => _showTotal = false);
      },
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            PanelTitle(_showTotal ? 'Total (yours)' : 'Cash'),
            const SizedBox(height: 6),
            Text(
              formatMoney(_showTotal ? store.ownTotal : cashAmount),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: (_showTotal ? store.ownTotal : cashAmount) < 0
                    ? kExpense
                    : kText,
              ),
            ),
            if (!_showTotal && pocket != null && pocketAmount != cashAmount)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'In pocket ${formatMoney(pocketAmount)}  ·  includes cash you borrowed or lent',
                  style: const TextStyle(color: kTextMuted, fontSize: 12),
                ),
              ),
            if (_showTotal) ...<Widget>[
              const SizedBox(height: 12),
              if (pocket != null) _accountLine(pocket.name, cashAmount),
              ...bank.map(
                (Account account) =>
                    _accountLine(account.name, account.ownBalance),
              ),
              if (showIouTotal) ...<Widget>[
                const SizedBox(height: 6),
                _accountLine('Owed to you', store.owedToYou),
                _accountLine('You owe', -store.youOwe),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 6),
                  child: Row(
                    children: <Widget>[
                      const Expanded(
                        child: Text(
                          'Yours + IOUs',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        formatMoney(store.ownPlusIous),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: store.ownPlusIous < 0 ? kExpense : kText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Text(
                'Swipe right to show cash only.',
                style: TextStyle(color: kTextMuted, fontSize: 11),
              ),
            ] else if (canSwipe)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  showIouTotal
                      ? 'Swipe left for bank total and cash + lend/borrow.'
                      : 'Swipe left for total (cash + bank).',
                  style: const TextStyle(color: kTextMuted, fontSize: 11),
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

  Future<void> _settle(BuildContext context, PersonBalance person) async {
    final bool theyOwe = person.net > 0;
    final double amount = person.net.abs();
    final Account? account = store.cashAccount;
    final String accountName = account?.name ?? 'Cash';
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: kSurface,
        title: Text(theyOwe ? 'Collect from ${person.name}?' : 'Pay ${person.name}?'),
        content: Text(
          theyOwe
              ? 'Take ${formatMoney(amount)} into $accountName to settle. Your cash goes up.'
              : 'Pay ${formatMoney(amount)} from $accountName to settle. Your cash goes down.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Settle'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final int? id = store.settlePerson(person, accountId: account?.id);
      if (!context.mounted || id == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            theyOwe
                ? 'Collected ${formatMoney(amount)} from ${person.name}.'
                : 'Paid ${formatMoney(amount)} to ${person.name}.',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => store.deleteTransaction(id),
          ),
          persist: false,
          duration: const Duration(seconds: 5),
          showCloseIcon: true,
        ),
      );
    }
  }

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
          const SizedBox(height: 6),
          Text(
            'Yours + IOUs  ${formatMoney(store.ownPlusIous)}',
            style: const TextStyle(color: kTextMuted, fontSize: 12),
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
                    const SizedBox(width: 4),
                    TextButton.icon(
                      onPressed: () => _settle(context, person),
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Settle'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: theyOwe ? kLend : kBorrow,
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
