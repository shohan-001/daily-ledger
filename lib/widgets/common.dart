import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models.dart';
import '../store.dart';

/// A bordered dark box. Used everywhere instead of [Card] so the look does not
/// depend on Flutter's shifting card sub-theme.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kSurface,
          border: Border.all(color: kBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        child: child,
      );
}

class PanelTitle extends StatelessWidget {
  const PanelTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: const TextStyle(
                color: kTextMuted,
                fontSize: 11,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      );
}

/// Hand-rolled progress bar: no animation, no LinearProgressIndicator
/// deprecation churn. [value] is clamped to 0..1.
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.value,
    this.color = kAccent,
    this.height = 8,
  });

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: Container(
          height: height,
          color: kSurfaceAlt,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: value.isFinite ? value.clamp(0.0, 1.0) : 0.0,
            child: Container(color: color),
          ),
        ),
      );
}

/// `< August 2026 >` with a jump-back-to-today button.
class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final AppStore store = context.watch<AppStore>();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          tooltip: 'Previous month',
          icon: const Icon(Icons.chevron_left),
          onPressed: store.previousMonth,
        ),
        SizedBox(
          width: 132,
          child: Text(
            formatMonth(store.month),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          icon: const Icon(Icons.chevron_right),
          onPressed: store.nextMonth,
        ),
        if (!store.isCurrentMonth)
          TextButton(
            onPressed: () => store.showMonth(DateTime.now()),
            child: const Text('Today'),
          ),
      ],
    );
  }
}

class TypeBadge extends StatelessWidget {
  const TypeBadge(this.type, {super.key});

  final TxType type;

  @override
  Widget build(BuildContext context) {
    final Color color = colorForType(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: kSurfaceAlt,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color),
      ),
      child: Text(
        type.label,
        style: TextStyle(color: color, fontSize: 11),
      ),
    );
  }
}

Color colorForType(TxType type) => switch (type) {
      TxType.expense => kExpense,
      TxType.income => kAccent,
      TxType.transfer => kTransfer,
      TxType.lend => kLend,
      TxType.borrow => kBorrow,
    };

IconData iconForType(TxType type, {String? categoryIconKey}) => switch (type) {
      TxType.transfer => Icons.swap_horiz,
      TxType.lend => Icons.call_made,
      TxType.borrow => Icons.call_received,
      _ => iconForKey(categoryIconKey),
    };

/// One row in any transaction list.
class TxnTile extends StatelessWidget {
  const TxnTile({super.key, required this.txn, this.onTap});

  final Txn txn;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppStore store = context.read<AppStore>();
    final Category? category = store.categoryById(txn.categoryId);
    final Color color = colorForType(txn.type);

    final String title = switch (txn.type) {
      TxType.transfer =>
        '${store.accountName(txn.accountId)} → ${store.accountName(txn.toAccountId)}',
      TxType.lend =>
        txn.person.isEmpty ? 'Lent' : 'Lent to ${txn.person}',
      TxType.borrow =>
        txn.person.isEmpty ? 'Borrowed' : 'Borrowed from ${txn.person}',
      _ => category?.name ?? 'Uncategorised',
    };

    final List<String> subtitleParts = <String>[
      formatDateHeader(txn.date),
      if (txn.type != TxType.transfer) store.accountName(txn.accountId),
      if (txn.note.isNotEmpty) txn.note,
    ];

    final String amountText = switch (txn.type) {
      TxType.expense || TxType.lend => '-${formatMoney(txn.amount)}',
      TxType.income || TxType.borrow => '+${formatMoney(txn.amount)}',
      TxType.transfer => formatMoney(txn.amount),
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: kSurfaceAlt,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                iconForType(txn.type, categoryIconKey: category?.iconKey),
                size: 18,
                color: color,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      if (txn.isRecurring)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(Icons.repeat, size: 13, color: kTextMuted),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitleParts.join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kTextMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              amountText,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyHint extends StatelessWidget {
  const EmptyHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kTextMuted, fontSize: 13),
          ),
        ),
      );
}

/// Amount as it should appear inside a text field: `50` not `50.00`.
String amountFieldText(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2);

/// Small labelled dropdown used by the forms and filter bars.
class LabeledDropdown<T> extends StatelessWidget {
  const LabeledDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: const TextStyle(color: kTextMuted, fontSize: 12)),
          const SizedBox(height: 4),
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: kSurfaceAlt,
              border: Border.all(color: kBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<T>(
              value: value,
              items: items,
              onChanged: onChanged,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              dropdownColor: kSurfaceAlt,
              style: const TextStyle(color: kText, fontSize: 14),
              icon: const Icon(Icons.expand_more, size: 18, color: kTextMuted),
            ),
          ),
        ],
      );
}
