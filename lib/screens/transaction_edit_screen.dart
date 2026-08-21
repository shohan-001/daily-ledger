import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models.dart';
import '../store.dart';
import '../widgets/common.dart';

/// Opens the add/edit form. Pass [existing] to edit, [preset] to pre-fill.
Future<void> openTransactionEditor(
  BuildContext context, {
  Txn? existing,
  Preset? preset,
}) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (BuildContext _) =>
          TransactionEditScreen(existing: existing, preset: preset),
    ),
  );
}

/// The screen used most often, so it keeps its own local state: nothing here
/// listens to [AppStore], which means typing an amount rebuilds this form only.
class TransactionEditScreen extends StatefulWidget {
  const TransactionEditScreen({super.key, this.existing, this.preset});

  final Txn? existing;
  final Preset? preset;

  @override
  State<TransactionEditScreen> createState() => _TransactionEditScreenState();
}

class _TransactionEditScreenState extends State<TransactionEditScreen> {
  late final AppStore _store;
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late final TextEditingController _person;

  late TxType _type;
  int? _accountId;
  int? _toAccountId;
  int? _categoryId;
  late DateTime _date;
  bool _inKind = false;

  @override
  void initState() {
    super.initState();
    _store = context.read<AppStore>();
    final Txn? existing = widget.existing;
    final Preset? preset = widget.preset;

    _type = existing?.type ?? preset?.type ?? TxType.expense;
    _date = existing?.date ?? DateTime.now();
    _amount = TextEditingController(
      text: existing != null
          ? amountFieldText(existing.amount)
          : preset != null
              ? amountFieldText(preset.amount)
              : '',
    );
    _note = TextEditingController(text: existing?.note ?? preset?.note ?? '');
    _person = TextEditingController(text: existing?.person ?? '');
    _accountId = existing?.accountId ?? preset?.accountId ?? _firstAccountId();
    _toAccountId = existing?.toAccountId;
    _categoryId = existing?.categoryId ??
        preset?.categoryId ??
        _firstCategoryId(_type);
    _inKind = existing?.inKind ?? false;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _person.dispose();
    super.dispose();
  }

  int? _firstAccountId() =>
      _store.accounts.isEmpty ? null : _store.accounts.first.id;

  int? _firstCategoryId(TxType type) {
    final List<Category> options = _store.categoriesOfType(type);
    return options.isEmpty ? null : options.first.id;
  }

  void _applyPreset(Preset preset) {
    setState(() {
      _type = preset.type;
      _amount.text = amountFieldText(preset.amount);
      _note.text = preset.note;
      _accountId = preset.accountId ?? _accountId ?? _firstAccountId();
      _categoryId = preset.type.usesCategory
          ? (preset.categoryId ?? _firstCategoryId(preset.type))
          : null;
      _toAccountId = null;
      if (!preset.type.usesPerson) _inKind = false;
    });
  }

  void _changeType(TxType type) {
    setState(() {
      _type = type;
      if (type == TxType.transfer) {
        _categoryId = null;
        final Iterable<Account> others =
            _store.accounts.where((Account a) => a.id != _accountId);
        if (_toAccountId == null && others.isNotEmpty) {
          _toAccountId = others.first.id;
        }
      } else {
        _toAccountId = null;
        if (type.usesCategory) {
          final Category? current = _store.categoryById(_categoryId);
          if (current == null || current.type != type) {
            _categoryId = _firstCategoryId(type);
          }
        } else {
          _categoryId = null;
        }
      }
      if (!type.usesPerson) _inKind = false;
    });
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _fail(String message) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: kSurfaceAlt),
      );

  void _save() {
    final double? amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      _fail('Enter an amount greater than zero.');
      return;
    }
    if (_accountId == null) {
      _fail('Add an account in Settings first.');
      return;
    }
    if (_type == TxType.transfer) {
      if (_toAccountId == null || _toAccountId == _accountId) {
        _fail('Pick two different accounts for a transfer.');
        return;
      }
    }
    if (_type.usesPerson && _person.text.trim().isEmpty) {
      _fail(
        _type == TxType.lend
            ? 'Who did you lend to?'
            : 'Who did you borrow from?',
      );
      return;
    }

    _store.saveTransaction(
      Txn(
        id: widget.existing?.id,
        amount: amount,
        type: _type,
        accountId: _accountId!,
        toAccountId: _type == TxType.transfer ? _toAccountId : null,
        categoryId: _type.usesCategory ? _categoryId : null,
        date: dayStart(_date),
        note: _note.text.trim(),
        person: _type.usesPerson ? _person.text.trim() : '',
        isRecurring: widget.existing?.isRecurring ?? false,
        inKind: _type.usesPerson ? _inKind : false,
        isSettlement: widget.existing?.isSettlement ?? false,
      ),
    );
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final int? id = widget.existing?.id;
    if (id == null) return;
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            backgroundColor: kSurface,
            title: const Text('Delete transaction?'),
            content: const Text('This cannot be undone.'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete', style: TextStyle(color: kExpense)),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    if (!mounted) return;
    _store.deleteTransaction(id);
    Navigator.of(context).pop();
  }

  String _iouHint() {
    if (_type == TxType.lend) {
      return _inKind
          ? 'They owe you. Your cash stays put until they settle.'
          : 'Money leaves this account. They owe you.';
    }
    return _inKind
        ? 'You owe them (they paid for food, etc.). Cash stays put until you settle.'
        : 'Money arrives in this account. You owe them.';
  }

  @override
  Widget build(BuildContext context) {
    final bool editing = widget.existing != null;
    final List<Category> categoryOptions =
        _type.usesCategory ? _store.categoriesOfType(_type) : const <Category>[];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kSurface,
        title: Text(editing ? 'Edit transaction' : 'Add transaction'),
        actions: <Widget>[
          if (editing)
            IconButton(
              tooltip: 'Delete',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline, color: kExpense),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
            children: <Widget>[
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: <Widget>[
                    if (!editing && _store.presets.isNotEmpty) ...<Widget>[
                      const PanelTitle('Quick add'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _store.presets
                            .map(
                              (Preset preset) => ActionChip(
                                backgroundColor: kSurfaceAlt,
                                side: const BorderSide(color: kBorder),
                                label: Text(
                                  '${preset.label} · ${amountFieldText(preset.amount)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                onPressed: () => _applyPreset(preset),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 20),
                    ],
                    TextField(
                      controller: _amount,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _save(),
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: fieldDecoration(
                        'Amount',
                        prefixText: '$kCurrencySymbol  ',
                        hint: '0',
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: TxType.values
                          .map(
                            (TxType type) => ChoiceChip(
                              label: Text(type.label),
                              selected: _type == type,
                              backgroundColor: kSurfaceAlt,
                              selectedColor: colorForType(type).withValues(alpha: 0.22),
                              side: BorderSide(
                                color: _type == type
                                    ? colorForType(type)
                                    : kBorder,
                              ),
                              showCheckmark: false,
                              onSelected: (_) => _changeType(type),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 18),
                    _AccountPicker(
                      label: switch (_type) {
                        TxType.transfer || TxType.lend => 'From account',
                        TxType.borrow => 'Into account',
                        _ => 'Account',
                      },
                      accounts: _store.accounts,
                      selectedId: _accountId,
                      onChanged: (int id) => setState(() {
                        _accountId = id;
                        if (_toAccountId == id) _toAccountId = null;
                      }),
                    ),
                    if (_type == TxType.transfer) ...<Widget>[
                      const SizedBox(height: 14),
                      _AccountPicker(
                        label: 'To account',
                        accounts: _store.accounts
                            .where((Account a) => a.id != _accountId)
                            .toList(),
                        selectedId: _toAccountId,
                        onChanged: (int id) => setState(() => _toAccountId = id),
                      ),
                    ],
                    if (_type.usesPerson) ...<Widget>[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          ChoiceChip(
                            label: Text(
                              _type == TxType.lend
                                  ? 'I gave / paid cash'
                                  : 'I received cash',
                            ),
                            selected: !_inKind,
                            backgroundColor: kSurfaceAlt,
                            selectedColor: kAccentFaint,
                            side: BorderSide(
                              color: !_inKind ? kAccent : kBorder,
                            ),
                            showCheckmark: false,
                            onSelected: (_) => setState(() => _inKind = false),
                          ),
                          ChoiceChip(
                            label: Text(
                              _type == TxType.lend
                                  ? 'No cash yet (goods / tab)'
                                  : 'They paid for me (food / goods)',
                            ),
                            selected: _inKind,
                            backgroundColor: kSurfaceAlt,
                            selectedColor: kAccentFaint,
                            side: BorderSide(
                              color: _inKind ? kAccent : kBorder,
                            ),
                            showCheckmark: false,
                            onSelected: (_) => setState(() => _inKind = true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _iouHint(),
                        style: const TextStyle(color: kTextMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _person,
                        textCapitalization: TextCapitalization.words,
                        decoration: fieldDecoration(
                          _type == TxType.lend ? 'Lent to' : 'Borrowed from',
                          hint: "Friend's name",
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                    ],
                    if (_type.usesCategory) ...<Widget>[
                      const SizedBox(height: 16),
                      LabeledDropdown<int?>(
                        label: 'Category',
                        value: categoryOptions
                                .any((Category c) => c.id == _categoryId)
                            ? _categoryId
                            : null,
                        items: <DropdownMenuItem<int?>>[
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Uncategorised'),
                          ),
                          ...categoryOptions.map(
                            (Category c) => DropdownMenuItem<int?>(
                              value: c.id,
                              child: Row(
                                children: <Widget>[
                                  Icon(iconForKey(c.iconKey), size: 16),
                                  const SizedBox(width: 8),
                                  Text(c.name),
                                ],
                              ),
                            ),
                          ),
                        ],
                        onChanged: (int? value) =>
                            setState(() => _categoryId = value),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Text(
                      'Date',
                      style: TextStyle(color: kTextMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed: _pickDate,
                          icon: const Icon(Icons.calendar_today, size: 15),
                          label: Text(formatDate(_date)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: kBorder),
                            foregroundColor: kText,
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () =>
                              setState(() => _date = DateTime.now()),
                          child: const Text('Today'),
                        ),
                        TextButton(
                          onPressed: () => setState(
                            () => _date = DateTime.now()
                                .subtract(const Duration(days: 1)),
                          ),
                          child: const Text('Yesterday'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _note,
                      decoration: fieldDecoration('Note (optional)'),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _save(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _save,
                    child: Text(editing ? 'Save changes' : 'Add transaction'),
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _AccountPicker extends StatelessWidget {
  const _AccountPicker({
    required this.label,
    required this.accounts,
    required this.selectedId,
    required this.onChanged,
  });

  final String label;
  final List<Account> accounts;
  final int? selectedId;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: const TextStyle(color: kTextMuted, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: accounts
                .map(
                  (Account account) => ChoiceChip(
                    label: Text(account.name),
                    selected: account.id == selectedId,
                    backgroundColor: kSurfaceAlt,
                    selectedColor: kAccentFaint,
                    side: BorderSide(
                      color: account.id == selectedId ? kAccent : kBorder,
                    ),
                    showCheckmark: false,
                    onSelected: (_) => onChanged(account.id!),
                  ),
                )
                .toList(),
          ),
        ],
      );
}
