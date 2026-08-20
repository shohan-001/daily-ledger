import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models.dart';
import '../store.dart';
import '../widgets/common.dart';
import 'transaction_edit_screen.dart';

enum _Range { thisMonth, lastMonth, last30Days, thisYear, all, custom }

String _rangeLabel(_Range range) => switch (range) {
      _Range.thisMonth => 'This month',
      _Range.lastMonth => 'Last month',
      _Range.last30Days => 'Last 30 days',
      _Range.thisYear => 'This year',
      _Range.all => 'All time',
      _Range.custom => 'Custom…',
    };

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final TextEditingController _search = TextEditingController();

  _Range _range = _Range.thisMonth;
  DateTimeRange? _customRange;
  int? _accountId;
  int? _categoryId;
  TxType? _type;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  DateTime? get _from {
    final DateTime now = DateTime.now();
    return switch (_range) {
      _Range.thisMonth => monthStart(now),
      _Range.lastMonth => monthStart(addMonths(now, -1)),
      _Range.last30Days => dayStart(now).subtract(const Duration(days: 30)),
      _Range.thisYear => DateTime(now.year),
      _Range.all => null,
      _Range.custom => _customRange?.start,
    };
  }

  DateTime? get _to {
    final DateTime now = DateTime.now();
    return switch (_range) {
      _Range.thisMonth => monthEnd(now),
      _Range.lastMonth => monthEnd(addMonths(now, -1)),
      _Range.last30Days => dayStart(now),
      _Range.thisYear => DateTime(now.year, 12, 31),
      _Range.all => null,
      _Range.custom => _customRange?.end,
    };
  }

  Future<void> _pickCustomRange() async {
    final DateTime now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 5, 12, 31),
      initialDateRange: _customRange ??
          DateTimeRange(start: monthStart(now), end: dayStart(now)),
    );
    if (picked == null) return;
    setState(() {
      _customRange = picked;
      _range = _Range.custom;
    });
  }

  void _resetFilters() => setState(() {
        _range = _Range.thisMonth;
        _customRange = null;
        _accountId = null;
        _categoryId = null;
        _type = null;
        _search.clear();
      });

  @override
  Widget build(BuildContext context) {
    final AppStore store = context.watch<AppStore>();
    final List<Txn> results = store.query(
      from: _from,
      to: _to,
      accountId: _accountId,
      categoryId: _categoryId,
      type: _type,
      search: _search.text,
    );

    double out = 0;
    double income = 0;
    double lent = 0;
    double borrowed = 0;
    for (final Txn txn in results) {
      if (txn.type == TxType.expense) out += txn.amount;
      if (txn.type == TxType.income) income += txn.amount;
      if (txn.type == TxType.lend) lent += txn.amount;
      if (txn.type == TxType.borrow) borrowed += txn.amount;
    }

    return ListView(
      padding: pagePadding(),
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(
              child: Text(
                'Transactions',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '${results.length} shown',
              style: const TextStyle(color: kTextMuted, fontSize: 12),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: _resetFilters,
              child: const Text('Reset filters'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Panel(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: <Widget>[
              SizedBox(
                width: 230,
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: fieldDecoration(
                    'Search notes or names',
                    suffix: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => setState(_search.clear),
                          ),
                  ),
                ),
              ),
              SizedBox(
                width: 160,
                child: LabeledDropdown<_Range>(
                  label: 'Period',
                  value: _range,
                  items: _Range.values
                      .map(
                        (_Range r) => DropdownMenuItem<_Range>(
                          value: r,
                          child: Text(_rangeLabel(r)),
                        ),
                      )
                      .toList(),
                  onChanged: (_Range? value) {
                    if (value == null) return;
                    if (value == _Range.custom) {
                      _pickCustomRange();
                    } else {
                      setState(() => _range = value);
                    }
                  },
                ),
              ),
              SizedBox(
                width: 150,
                child: LabeledDropdown<int?>(
                  label: 'Account',
                  value: _accountId,
                  items: <DropdownMenuItem<int?>>[
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('All accounts'),
                    ),
                    ...store.accounts.map(
                      (Account a) => DropdownMenuItem<int?>(
                        value: a.id,
                        child: Text(a.name),
                      ),
                    ),
                  ],
                  onChanged: (int? value) =>
                      setState(() => _accountId = value),
                ),
              ),
              SizedBox(
                width: 180,
                child: LabeledDropdown<int?>(
                  label: 'Category',
                  value: _categoryId,
                  items: <DropdownMenuItem<int?>>[
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('All categories'),
                    ),
                    ...store.categories.map(
                      (Category c) => DropdownMenuItem<int?>(
                        value: c.id,
                        child: Text(c.name),
                      ),
                    ),
                  ],
                  onChanged: (int? value) =>
                      setState(() => _categoryId = value),
                ),
              ),
              SizedBox(
                width: 150,
                child: LabeledDropdown<TxType?>(
                  label: 'Type',
                  value: _type,
                  items: <DropdownMenuItem<TxType?>>[
                    const DropdownMenuItem<TxType?>(
                      value: null,
                      child: Text('All types'),
                    ),
                    ...TxType.values.map(
                      (TxType t) => DropdownMenuItem<TxType?>(
                        value: t,
                        child: Text(t.label),
                      ),
                    ),
                  ],
                  onChanged: (TxType? value) => setState(() => _type = value),
                ),
              ),
            ],
          ),
        ),
        if (_range == _Range.custom && _customRange != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${formatDate(_customRange!.start)} → ${formatDate(_customRange!.end)}',
              style: const TextStyle(color: kTextMuted, fontSize: 12),
            ),
          ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Expanded(
              child: _Stat(label: 'Spent', value: out, color: kExpense),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Stat(label: 'Received', value: income, color: kAccent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Stat(
                label: 'Net',
                value: income - out,
                color: income - out < 0 ? kExpense : kAccent,
                signed: true,
              ),
            ),
          ],
        ),
        if (lent > 0 || borrowed > 0) ...<Widget>[
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: _Stat(label: 'Lent', value: lent, color: kLend),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Stat(label: 'Borrowed', value: borrowed, color: kBorrow),
              ),
              const SizedBox(width: 12),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ],
        const SizedBox(height: 14),
        Panel(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: results.isEmpty
              ? const EmptyHint('Nothing matches these filters.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _groupedRows(context, results),
                ),
        ),
      ],
    );
  }

  /// Flat list of date headers followed by their transactions.
  List<Widget> _groupedRows(BuildContext context, List<Txn> results) {
    final Map<DateTime, double> spentPerDay = <DateTime, double>{};
    for (final Txn txn in results) {
      if (txn.type != TxType.expense) continue;
      final DateTime day = dayStart(txn.date);
      spentPerDay[day] = (spentPerDay[day] ?? 0) + txn.amount;
    }

    final List<Widget> rows = <Widget>[];
    DateTime? currentDay;
    for (int i = 0; i < results.length; i++) {
      final Txn txn = results[i];
      final DateTime day = dayStart(txn.date);
      if (currentDay == null || day != currentDay) {
        currentDay = day;
        final double dayTotal = spentPerDay[day] ?? 0;
        rows.add(
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 6 : 14, bottom: 2),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    formatDateHeader(day),
                    style: const TextStyle(
                      color: kTextMuted,
                      fontSize: 11,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (dayTotal > 0)
                  Text(
                    '-${formatMoney(dayTotal)}',
                    style: const TextStyle(color: kTextMuted, fontSize: 11),
                  ),
              ],
            ),
          ),
        );
      }
      rows.add(
        TxnTile(
          txn: txn,
          onTap: () => openTransactionEditor(context, existing: txn),
        ),
      );
    }
    return rows;
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.color,
    this.signed = false,
  });

  final String label;
  final double value;
  final Color color;
  final bool signed;

  @override
  Widget build(BuildContext context) => Panel(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: const TextStyle(color: kTextMuted, fontSize: 11)),
            const SizedBox(height: 4),
            Text(
              formatMoney(value, signed: signed),
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}
