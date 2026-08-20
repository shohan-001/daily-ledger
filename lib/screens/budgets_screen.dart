import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models.dart';
import '../store.dart';
import '../widgets/category_bars.dart';
import '../widgets/common.dart';

class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppStore store = context.watch<AppStore>();
    final List<Category> expenseCategories =
        store.categoriesOfType(TxType.expense);

    return ListView(
      padding: pagePadding(),
      children: <Widget>[
        if (kIsMobile) ...<Widget>[
          const Text(
            'Budgets',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const MonthSwitcher(),
        ] else
          const Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Budgets',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ),
              MonthSwitcher(),
            ],
          ),
        const SizedBox(height: 18),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PanelTitle(
                'Overall monthly limit',
                trailing: TextButton(
                  onPressed: () => showLimitDialog(
                    context,
                    title: 'Overall monthly limit',
                    categoryId: null,
                    current: store.overallLimit,
                  ),
                  child: Text(store.overallLimit == null ? 'Set' : 'Edit'),
                ),
              ),
              const SizedBox(height: 8),
              _LimitRow(
                spent: store.monthExpense,
                limit: store.overallLimit,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const PanelTitle('Spending by category'),
              const SizedBox(height: 12),
              CategoryBarsChart(data: _chartData(store)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const PanelTitle('Per-category limits'),
              const SizedBox(height: 4),
              if (expenseCategories.isEmpty)
                const EmptyHint('No expense categories yet.')
              else
                ...expenseCategories.map(
                  (Category category) => _CategoryBudgetRow(
                    category: category,
                    spent: store.spentInCategory(category.id!),
                    limit: store.limitForCategory(category.id!),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Limits are a single number per category per month. No rollover, no '
          'custom periods — by design.',
          style: TextStyle(color: kTextMuted, fontSize: 12),
        ),
      ],
    );
  }

  List<CategorySpend> _chartData(AppStore store) {
    final List<CategorySpend> data = <CategorySpend>[];
    final List<MapEntry<int?, double>> entries =
        store.spentByCategory.entries.toList()
          ..sort(
            (MapEntry<int?, double> a, MapEntry<int?, double> b) =>
                b.value.compareTo(a.value),
          );
    for (int i = 0; i < entries.length && i < 8; i++) {
      if (entries[i].value <= 0) continue;
      data.add(
        CategorySpend(
          label: store.categoryName(entries[i].key),
          amount: entries[i].value,
          color: kChartColors[i % kChartColors.length],
        ),
      );
    }
    return data;
  }
}

class _LimitRow extends StatelessWidget {
  const _LimitRow({required this.spent, required this.limit});

  final double spent;
  final double? limit;

  @override
  Widget build(BuildContext context) {
    if (limit == null) {
      return Text(
        '${formatMoney(spent)} spent · no limit set',
        style: const TextStyle(color: kTextMuted, fontSize: 13),
      );
    }
    final bool over = spent > limit!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              formatMoney(spent),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: over ? kExpense : kText,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'of ${formatMoney(limit!)}',
              style: const TextStyle(color: kTextMuted, fontSize: 13),
            ),
            const Spacer(),
            Text(
              over
                  ? '${formatMoney(spent - limit!)} over'
                  : '${formatMoney(limit! - spent)} left',
              style: TextStyle(
                color: over ? kExpense : kTextMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ProgressBar(
          value: spent / limit!,
          color: over ? kExpense : kAccent,
        ),
      ],
    );
  }
}

class _CategoryBudgetRow extends StatelessWidget {
  const _CategoryBudgetRow({
    required this.category,
    required this.spent,
    required this.limit,
  });

  final Category category;
  final double spent;
  final double? limit;

  @override
  Widget build(BuildContext context) {
    final bool over = limit != null && spent > limit!;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showLimitDialog(
        context,
        title: '${category.name} monthly limit',
        categoryId: category.id,
        current: limit,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(iconForKey(category.iconKey), size: 17, color: kTextMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    category.name,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                Text(
                  limit == null
                      ? '${formatMoney(spent)} · no limit'
                      : '${formatMoney(spent)} / ${formatMoney(limit!)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: over ? kExpense : kTextMuted,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.edit, size: 13, color: kTextMuted),
              ],
            ),
            if (limit != null) ...<Widget>[
              const SizedBox(height: 8),
              ProgressBar(
                value: spent / limit!,
                height: 6,
                color: over ? kExpense : kAccent,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sets or clears one monthly limit. `categoryId == null` edits the overall one.
Future<void> showLimitDialog(
  BuildContext context, {
  required String title,
  required int? categoryId,
  required double? current,
}) =>
    showDialog<void>(
      context: context,
      builder: (BuildContext _) => _LimitDialog(
        title: title,
        categoryId: categoryId,
        current: current,
      ),
    );

class _LimitDialog extends StatefulWidget {
  const _LimitDialog({
    required this.title,
    required this.categoryId,
    required this.current,
  });

  final String title;
  final int? categoryId;
  final double? current;

  @override
  State<_LimitDialog> createState() => _LimitDialogState();
}

class _LimitDialogState extends State<_LimitDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.current == null ? '' : amountFieldText(widget.current!),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final AppStore store = context.read<AppStore>();
    final double value = double.tryParse(_controller.text.trim()) ?? 0;
    store.setBudget(widget.categoryId, value);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: kSurface,
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 300,
          child: TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            onSubmitted: (_) => _save(),
            decoration: fieldDecoration(
              'Monthly limit',
              prefixText: '$kCurrencySymbol  ',
              hint: 'Leave empty to remove',
            ),
          ),
        ),
        actions: <Widget>[
          if (widget.current != null)
            TextButton(
              onPressed: () {
                context.read<AppStore>().clearBudget(widget.categoryId);
                Navigator.of(context).pop();
              },
              child: const Text('Remove', style: TextStyle(color: kExpense)),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      );
}
