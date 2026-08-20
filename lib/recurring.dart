import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'constants.dart';
import 'models.dart';
import 'store.dart';

/// Shown once at launch when monthly rules are due. Nothing is ever posted
/// without an explicit confirmation here.
Future<void> showDueRulesDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (BuildContext _) => const _DueRulesDialog(),
    );

class _DueRulesDialog extends StatefulWidget {
  const _DueRulesDialog();

  @override
  State<_DueRulesDialog> createState() => _DueRulesDialogState();
}

class _DueRulesDialogState extends State<_DueRulesDialog> {
  /// Confirming or skipping advances the rule by one month; if it was overdue
  /// by several months the next occurrence simply reappears in this list.
  void _closeIfDone(AppStore store) {
    if (store.dueRules().isEmpty) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final AppStore store = context.watch<AppStore>();
    final List<RecurringRule> due = store.dueRules();

    return AlertDialog(
      backgroundColor: kSurface,
      title: const Text('Recurring transactions due', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
            const Text(
              'These monthly rules have reached their due date. Add the ones '
              'that really happened.',
              style: TextStyle(color: kTextMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            ...due.map(
              (RecurringRule rule) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kSurfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kBorder),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${formatMoney(rule.amount)} · '
                            '${store.categoryName(rule.categoryId)}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            <String>[
                              'Due ${formatDate(rule.nextDueDate)}',
                              store.accountName(rule.accountId),
                              if (rule.note.isNotEmpty) rule.note,
                            ].join('  ·  '),
                            style: const TextStyle(
                              color: kTextMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        store.skipRule(rule);
                        _closeIfDone(store);
                      },
                      child: const Text('Skip'),
                    ),
                    const SizedBox(width: 6),
                    FilledButton(
                      onPressed: () {
                        store.confirmRule(rule);
                        _closeIfDone(store);
                      },
                      child: const Text('Add'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Decide later'),
        ),
      ],
    );
  }
}
