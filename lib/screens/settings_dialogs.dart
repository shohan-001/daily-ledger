import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models.dart';
import '../store.dart';
import '../widgets/common.dart';

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

final List<TextInputFormatter> _numberOnly = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
];

AlertDialog _dialog({
  required String title,
  required Widget body,
  required List<Widget> actions,
}) =>
    AlertDialog(
      backgroundColor: kSurface,
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(child: body),
      ),
      actions: actions,
    );

Widget _deleteButton({required VoidCallback onPressed}) => TextButton(
      onPressed: onPressed,
      child: const Text('Delete', style: TextStyle(color: kExpense)),
    );

// ---------------------------------------------------------------------------
// Accounts
// ---------------------------------------------------------------------------

Future<void> showAccountDialog(BuildContext context, {Account? account}) =>
    showDialog<void>(
      context: context,
      builder: (BuildContext _) => _AccountDialog(account: account),
    );

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({this.account});

  final Account? account;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.account?.name ?? '');
  late final TextEditingController _starting = TextEditingController(
    text: amountFieldText(widget.account?.startingBalance ?? 0),
  );

  @override
  void dispose() {
    _name.dispose();
    _starting.dispose();
    super.dispose();
  }

  void _save() {
    final String name = _name.text.trim();
    if (name.isEmpty) return;
    final AppStore store = context.read<AppStore>();
    store.saveAccount(
      Account(
        id: widget.account?.id,
        name: name,
        startingBalance: double.tryParse(_starting.text.trim()) ?? 0,
        currentBalance: widget.account?.currentBalance ?? 0,
        sortOrder: widget.account?.sortOrder ?? 0,
      ),
    );
    Navigator.of(context).pop();
  }

  void _delete() {
    final int? id = widget.account?.id;
    if (id == null) return;
    final bool removed = context.read<AppStore>().deleteAccount(id);
    if (!removed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: kSurfaceAlt,
          content: Text(
            'This account still has transactions. Move or delete them first.',
          ),
        ),
      );
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => _dialog(
        title: widget.account == null ? 'New account' : 'Edit account',
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _name,
              autofocus: true,
              decoration: fieldDecoration('Name', hint: 'Cash, Bank Card, …'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _starting,
              keyboardType: TextInputType.number,
              inputFormatters: _numberOnly,
              onSubmitted: (_) => _save(),
              decoration: fieldDecoration(
                'Starting balance',
                prefixText: '$kCurrencySymbol  ',
              ),
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'The current balance is always starting balance plus every '
                'transaction, so it is not editable.',
                style: TextStyle(color: kTextMuted, fontSize: 11),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          if (widget.account != null) _deleteButton(onPressed: _delete),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      );
}

// ---------------------------------------------------------------------------
// Categories
// ---------------------------------------------------------------------------

Future<void> showCategoryDialog(BuildContext context, {Category? category}) =>
    showDialog<void>(
      context: context,
      builder: (BuildContext _) => _CategoryDialog(category: category),
    );

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({this.category});

  final Category? category;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.category?.name ?? '');
  late TxType _type = widget.category?.type ?? TxType.expense;
  late String _iconKey = widget.category?.iconKey ?? 'category';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final String name = _name.text.trim();
    if (name.isEmpty) return;
    context.read<AppStore>().saveCategory(
          Category(
            id: widget.category?.id,
            name: name,
            type: _type,
            iconKey: _iconKey,
            sortOrder: widget.category?.sortOrder ?? 0,
          ),
        );
    Navigator.of(context).pop();
  }

  void _delete() {
    final int? id = widget.category?.id;
    if (id == null) return;
    context.read<AppStore>().deleteCategory(id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => _dialog(
        title: widget.category == null ? 'New category' : 'Edit category',
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _name,
              autofocus: true,
              onSubmitted: (_) => _save(),
              decoration: fieldDecoration('Name'),
            ),
            const SizedBox(height: 12),
            SegmentedButton<TxType>(
              segments: const <ButtonSegment<TxType>>[
                ButtonSegment<TxType>(
                  value: TxType.expense,
                  label: Text('Expense'),
                ),
                ButtonSegment<TxType>(
                  value: TxType.income,
                  label: Text('Income'),
                ),
              ],
              selected: <TxType>{_type},
              showSelectedIcon: false,
              onSelectionChanged: (Set<TxType> selection) =>
                  setState(() => _type = selection.first),
            ),
            const SizedBox(height: 14),
            const Text('Icon', style: TextStyle(color: kTextMuted, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: kCategoryIcons.keys
                  .map(
                    (String key) => InkWell(
                      onTap: () => setState(() => _iconKey = key),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: kSurfaceAlt,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: key == _iconKey ? kAccent : kBorder,
                          ),
                        ),
                        child: Icon(
                          kCategoryIcons[key],
                          size: 17,
                          color: key == _iconKey ? kAccent : kTextMuted,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
        actions: <Widget>[
          if (widget.category != null) _deleteButton(onPressed: _delete),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      );
}

// ---------------------------------------------------------------------------
// Quick-add presets
// ---------------------------------------------------------------------------

Future<void> showPresetDialog(BuildContext context, {Preset? preset}) =>
    showDialog<void>(
      context: context,
      builder: (BuildContext _) => _PresetDialog(preset: preset),
    );

class _PresetDialog extends StatefulWidget {
  const _PresetDialog({this.preset});

  final Preset? preset;

  @override
  State<_PresetDialog> createState() => _PresetDialogState();
}

class _PresetDialogState extends State<_PresetDialog> {
  late final TextEditingController _label =
      TextEditingController(text: widget.preset?.label ?? '');
  late final TextEditingController _amount = TextEditingController(
    text: widget.preset == null ? '' : amountFieldText(widget.preset!.amount),
  );
  late final TextEditingController _note =
      TextEditingController(text: widget.preset?.note ?? '');
  late TxType _type = widget.preset?.type ?? TxType.expense;
  int? _accountId;
  int? _categoryId;

  @override
  void initState() {
    super.initState();
    _accountId = widget.preset?.accountId;
    _categoryId = widget.preset?.categoryId;
  }

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final String label = _label.text.trim();
    final double amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (label.isEmpty || amount <= 0) return;
    context.read<AppStore>().savePreset(
          Preset(
            id: widget.preset?.id,
            label: label,
            amount: amount,
            type: _type,
            accountId: _accountId,
            categoryId: _categoryId,
            note: _note.text.trim(),
            sortOrder: widget.preset?.sortOrder ?? 0,
          ),
        );
    Navigator.of(context).pop();
  }

  void _delete() {
    final int? id = widget.preset?.id;
    if (id == null) return;
    context.read<AppStore>().deletePreset(id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final AppStore store = context.read<AppStore>();
    final List<Category> categories = store.categoriesOfType(_type);
    return _dialog(
      title: widget.preset == null ? 'New quick add' : 'Edit quick add',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _label,
            autofocus: true,
            decoration: fieldDecoration('Label', hint: 'Bus fare'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: _numberOnly,
            decoration: fieldDecoration(
              'Amount',
              prefixText: '$kCurrencySymbol  ',
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<TxType>(
            segments: const <ButtonSegment<TxType>>[
              ButtonSegment<TxType>(
                value: TxType.expense,
                label: Text('Expense'),
              ),
              ButtonSegment<TxType>(value: TxType.income, label: Text('Income')),
            ],
            selected: <TxType>{_type},
            showSelectedIcon: false,
            onSelectionChanged: (Set<TxType> selection) => setState(() {
              _type = selection.first;
              _categoryId = null;
            }),
          ),
          const SizedBox(height: 12),
          LabeledDropdown<int?>(
            label: 'Account',
            value: _accountId,
            items: <DropdownMenuItem<int?>>[
              const DropdownMenuItem<int?>(value: null, child: Text('Ask me')),
              ...store.accounts.map(
                (Account a) => DropdownMenuItem<int?>(
                  value: a.id,
                  child: Text(a.name),
                ),
              ),
            ],
            onChanged: (int? value) => setState(() => _accountId = value),
          ),
          const SizedBox(height: 12),
          LabeledDropdown<int?>(
            label: 'Category',
            value: categories.any((Category c) => c.id == _categoryId)
                ? _categoryId
                : null,
            items: <DropdownMenuItem<int?>>[
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('Uncategorised'),
              ),
              ...categories.map(
                (Category c) => DropdownMenuItem<int?>(
                  value: c.id,
                  child: Text(c.name),
                ),
              ),
            ],
            onChanged: (int? value) => setState(() => _categoryId = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            onSubmitted: (_) => _save(),
            decoration: fieldDecoration('Note (optional)'),
          ),
        ],
      ),
      actions: <Widget>[
        if (widget.preset != null) _deleteButton(onPressed: _delete),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Recurring rules
// ---------------------------------------------------------------------------

Future<void> showRuleDialog(BuildContext context, {RecurringRule? rule}) =>
    showDialog<void>(
      context: context,
      builder: (BuildContext _) => _RuleDialog(rule: rule),
    );

class _RuleDialog extends StatefulWidget {
  const _RuleDialog({this.rule});

  final RecurringRule? rule;

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.rule == null ? '' : amountFieldText(widget.rule!.amount),
  );
  late final TextEditingController _note =
      TextEditingController(text: widget.rule?.note ?? '');
  late TxType _type = widget.rule?.type ?? TxType.expense;
  late int _dayOfMonth = widget.rule?.dayOfMonth ?? 1;
  int? _accountId;
  int? _categoryId;

  @override
  void initState() {
    super.initState();
    final AppStore store = context.read<AppStore>();
    _accountId = widget.rule?.accountId ??
        (store.accounts.isEmpty ? null : store.accounts.first.id);
    _categoryId = widget.rule?.categoryId;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  DateTime get _nextDue {
    final RecurringRule? existing = widget.rule;
    if (existing != null && existing.dayOfMonth == _dayOfMonth) {
      return existing.nextDueDate;
    }
    return RecurringRule.nextDueForDay(_dayOfMonth);
  }

  void _save() {
    final double amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0 || _accountId == null) return;
    context.read<AppStore>().saveRule(
          RecurringRule(
            id: widget.rule?.id,
            amount: amount,
            type: _type,
            accountId: _accountId!,
            categoryId: _categoryId,
            note: _note.text.trim(),
            dayOfMonth: _dayOfMonth,
            nextDueDate: _nextDue,
            active: widget.rule?.active ?? true,
          ),
        );
    Navigator.of(context).pop();
  }

  void _delete() {
    final int? id = widget.rule?.id;
    if (id == null) return;
    context.read<AppStore>().deleteRule(id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final AppStore store = context.read<AppStore>();
    final List<Category> categories = store.categoriesOfType(_type);
    return _dialog(
      title: widget.rule == null ? 'New monthly rule' : 'Edit monthly rule',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: _numberOnly,
            decoration: fieldDecoration(
              'Amount',
              prefixText: '$kCurrencySymbol  ',
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<TxType>(
            segments: const <ButtonSegment<TxType>>[
              ButtonSegment<TxType>(
                value: TxType.expense,
                label: Text('Expense'),
              ),
              ButtonSegment<TxType>(value: TxType.income, label: Text('Income')),
            ],
            selected: <TxType>{_type},
            showSelectedIcon: false,
            onSelectionChanged: (Set<TxType> selection) => setState(() {
              _type = selection.first;
              _categoryId = null;
            }),
          ),
          const SizedBox(height: 12),
          LabeledDropdown<int?>(
            label: 'Account',
            value: _accountId,
            items: store.accounts
                .map(
                  (Account a) => DropdownMenuItem<int?>(
                    value: a.id,
                    child: Text(a.name),
                  ),
                )
                .toList(),
            onChanged: (int? value) => setState(() => _accountId = value),
          ),
          const SizedBox(height: 12),
          LabeledDropdown<int?>(
            label: 'Category',
            value: categories.any((Category c) => c.id == _categoryId)
                ? _categoryId
                : null,
            items: <DropdownMenuItem<int?>>[
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('Uncategorised'),
              ),
              ...categories.map(
                (Category c) => DropdownMenuItem<int?>(
                  value: c.id,
                  child: Text(c.name),
                ),
              ),
            ],
            onChanged: (int? value) => setState(() => _categoryId = value),
          ),
          const SizedBox(height: 12),
          LabeledDropdown<int>(
            label: 'Day of month',
            value: _dayOfMonth,
            items: List<DropdownMenuItem<int>>.generate(
              31,
              (int i) => DropdownMenuItem<int>(
                value: i + 1,
                child: Text('${i + 1}'),
              ),
            ),
            onChanged: (int? value) =>
                setState(() => _dayOfMonth = value ?? 1),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            onSubmitted: (_) => _save(),
            decoration: fieldDecoration('Note (optional)', hint: 'Boarding rent'),
          ),
          const SizedBox(height: 10),
          Text(
            'Next due: ${formatDate(_nextDue)} · you confirm it at launch, '
            'nothing is posted automatically.',
            style: const TextStyle(color: kTextMuted, fontSize: 11),
          ),
        ],
      ),
      actions: <Widget>[
        if (widget.rule != null) _deleteButton(onPressed: _delete),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
