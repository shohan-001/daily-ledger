import 'constants.dart';

/// Transaction kind. Categories only ever use [TxType.expense] or
/// [TxType.income]. Lend/borrow track IOUs against a person, not a category.
enum TxType {
  expense,
  income,
  transfer,
  lend,
  borrow;

  static TxType parse(String value) => TxType.values.firstWhere(
        (TxType t) => t.name == value,
        orElse: () => TxType.expense,
      );

  String get label => switch (this) {
        TxType.expense => 'Expense',
        TxType.income => 'Income',
        TxType.transfer => 'Transfer',
        TxType.lend => 'Lend',
        TxType.borrow => 'Borrow',
      };

  /// Food, rent, allowance, etc. — not used for transfers or IOUs.
  bool get usesCategory => this == TxType.expense || this == TxType.income;

  /// Friend's name on lend/borrow.
  bool get usesPerson => this == TxType.lend || this == TxType.borrow;
}

class Account {
  const Account({
    this.id,
    required this.name,
    this.startingBalance = 0,
    this.currentBalance = 0,
    this.ownBalance = 0,
    this.sortOrder = 0,
  });

  final int? id;
  final String name;
  final double startingBalance;

  /// Pocket: starting balance plus every cash movement, including cash IOUs.
  final double currentBalance;

  /// Yours: income, spend and transfers only — lend/borrow are excluded.
  final double ownBalance;
  final int sortOrder;

  factory Account.fromRow(Map<String, Object?> row) => Account(
        id: row['id'] as int,
        name: row['name'] as String,
        startingBalance: (row['starting_balance'] as num).toDouble(),
        currentBalance: (row['current_balance'] as num).toDouble(),
        ownBalance: (row['own_balance'] as num?)?.toDouble() ??
            (row['starting_balance'] as num).toDouble(),
        sortOrder: (row['sort_order'] as num).toInt(),
      );

  Account copyWith({String? name, double? startingBalance, int? sortOrder}) =>
      Account(
        id: id,
        name: name ?? this.name,
        startingBalance: startingBalance ?? this.startingBalance,
        currentBalance: currentBalance,
        ownBalance: ownBalance,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}

class Category {
  const Category({
    this.id,
    required this.name,
    required this.type,
    this.iconKey = 'category',
    this.sortOrder = 0,
  });

  final int? id;
  final String name;
  final TxType type;
  final String iconKey;
  final int sortOrder;

  factory Category.fromRow(Map<String, Object?> row) => Category(
        id: row['id'] as int,
        name: row['name'] as String,
        type: TxType.parse(row['type'] as String),
        iconKey: (row['icon'] as String?) ?? 'category',
        sortOrder: (row['sort_order'] as num).toInt(),
      );

  Category copyWith({
    String? name,
    TxType? type,
    String? iconKey,
    int? sortOrder,
  }) =>
      Category(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        iconKey: iconKey ?? this.iconKey,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}

class Txn {
  const Txn({
    this.id,
    required this.amount,
    required this.type,
    required this.accountId,
    this.toAccountId,
    this.categoryId,
    required this.date,
    this.note = '',
    this.person = '',
    this.isRecurring = false,
    this.inKind = false,
    this.isSettlement = false,
  });

  final int? id;
  final double amount;
  final TxType type;
  final int accountId;

  /// Destination account, only meaningful for [TxType.transfer].
  final int? toAccountId;
  final int? categoryId;
  final DateTime date;
  final String note;

  /// Who you lent to or borrowed from. Empty for other types.
  final String person;

  /// True when the row was created from a [RecurringRule].
  final bool isRecurring;

  /// Food, goods, a tab — the person owes / is owed, but cash did not move yet.
  final bool inKind;

  /// Posted by the settle tick. Always moves cash to close the IOU.
  final bool isSettlement;

  factory Txn.fromRow(Map<String, Object?> row) => Txn(
        id: row['id'] as int,
        amount: (row['amount'] as num).toDouble(),
        type: TxType.parse(row['type'] as String),
        accountId: (row['account_id'] as num).toInt(),
        toAccountId: (row['to_account_id'] as num?)?.toInt(),
        categoryId: (row['category_id'] as num?)?.toInt(),
        date: parseIsoDate(row['date'] as String),
        note: (row['note'] as String?) ?? '',
        person: (row['person'] as String?) ?? '',
        isRecurring: (row['is_recurring'] as num?)?.toInt() == 1,
        inKind: (row['in_kind'] as num?)?.toInt() == 1,
        isSettlement: (row['is_settlement'] as num?)?.toInt() == 1,
      );

  Txn copyWith({
    double? amount,
    TxType? type,
    int? accountId,
    int? toAccountId,
    int? categoryId,
    DateTime? date,
    String? note,
    String? person,
    bool? isRecurring,
    bool? inKind,
    bool? isSettlement,
  }) =>
      Txn(
        id: id,
        amount: amount ?? this.amount,
        type: type ?? this.type,
        accountId: accountId ?? this.accountId,
        toAccountId: toAccountId ?? this.toAccountId,
        categoryId: categoryId ?? this.categoryId,
        date: date ?? this.date,
        note: note ?? this.note,
        person: person ?? this.person,
        isRecurring: isRecurring ?? this.isRecurring,
        inKind: inKind ?? this.inKind,
        isSettlement: isSettlement ?? this.isSettlement,
      );

  /// Effect on pocket cash. Goods/tabs do not move it until you settle.
  double get signedAmount {
    if (type == TxType.transfer) return 0;
    if ((type == TxType.lend || type == TxType.borrow) && inKind) return 0;
    return switch (type) {
      TxType.expense || TxType.lend => -amount,
      TxType.income || TxType.borrow => amount,
      TxType.transfer => 0,
    };
  }
}

/// Running IOU with one person. [net] > 0 means they owe you.
class PersonBalance {
  const PersonBalance({
    required this.name,
    required this.lent,
    required this.borrowed,
  });

  final String name;
  final double lent;
  final double borrowed;

  /// Positive: they still owe you. Negative: you still owe them.
  double get net => lent - borrowed;
}

/// Monthly-only recurring template. Nothing is posted without confirmation.
class RecurringRule {
  const RecurringRule({
    this.id,
    required this.amount,
    required this.type,
    required this.accountId,
    this.categoryId,
    this.note = '',
    required this.dayOfMonth,
    required this.nextDueDate,
    this.active = true,
  });

  final int? id;
  final double amount;
  final TxType type;
  final int accountId;
  final int? categoryId;
  final String note;
  final int dayOfMonth;
  final DateTime nextDueDate;
  final bool active;

  factory RecurringRule.fromRow(Map<String, Object?> row) => RecurringRule(
        id: row['id'] as int,
        amount: (row['amount'] as num).toDouble(),
        type: TxType.parse(row['type'] as String),
        accountId: (row['account_id'] as num).toInt(),
        categoryId: (row['category_id'] as num?)?.toInt(),
        note: (row['note'] as String?) ?? '',
        dayOfMonth: (row['day_of_month'] as num).toInt(),
        nextDueDate: parseIsoDate(row['next_due_date'] as String),
        active: (row['active'] as num).toInt() == 1,
      );

  RecurringRule copyWith({
    double? amount,
    TxType? type,
    int? accountId,
    int? categoryId,
    String? note,
    int? dayOfMonth,
    DateTime? nextDueDate,
    bool? active,
  }) =>
      RecurringRule(
        id: id,
        amount: amount ?? this.amount,
        type: type ?? this.type,
        accountId: accountId ?? this.accountId,
        categoryId: categoryId ?? this.categoryId,
        note: note ?? this.note,
        dayOfMonth: dayOfMonth ?? this.dayOfMonth,
        nextDueDate: nextDueDate ?? this.nextDueDate,
        active: active ?? this.active,
      );

  bool isDue(DateTime today) =>
      active && !nextDueDate.isAfter(dayStart(today));

  /// First occurrence of [dayOfMonth] that is today or later.
  static DateTime nextDueForDay(int dayOfMonth, {DateTime? from}) {
    final DateTime today = dayStart(from ?? DateTime.now());
    final int lastDayThisMonth = DateTime(today.year, today.month + 1, 0).day;
    final DateTime thisMonth = DateTime(
      today.year,
      today.month,
      dayOfMonth > lastDayThisMonth ? lastDayThisMonth : dayOfMonth,
    );
    if (!thisMonth.isBefore(today)) return thisMonth;
    final DateTime next = DateTime(today.year, today.month + 1);
    final int lastDayNext = DateTime(next.year, next.month + 1, 0).day;
    return DateTime(
      next.year,
      next.month,
      dayOfMonth > lastDayNext ? lastDayNext : dayOfMonth,
    );
  }

  /// The occurrence after [nextDueDate], clamped to the length of the month.
  DateTime advanced() {
    final DateTime next = addMonths(DateTime(nextDueDate.year, nextDueDate.month, 1), 1);
    final int lastDay = DateTime(next.year, next.month + 1, 0).day;
    return DateTime(next.year, next.month, dayOfMonth > lastDay ? lastDay : dayOfMonth);
  }

  Txn toTransaction() => Txn(
        amount: amount,
        type: type,
        accountId: accountId,
        categoryId: categoryId,
        date: nextDueDate,
        note: note,
        isRecurring: true,
      );
}

/// One limit per category per month. `categoryId == null` is the overall limit.
class Budget {
  const Budget({this.id, this.categoryId, required this.monthlyLimit});

  final int? id;
  final int? categoryId;
  final double monthlyLimit;

  factory Budget.fromRow(Map<String, Object?> row) => Budget(
        id: row['id'] as int,
        categoryId: (row['category_id'] as num?)?.toInt(),
        monthlyLimit: (row['monthly_limit'] as num).toDouble(),
      );
}

/// A one-tap template for the Add Transaction form (e.g. "Bus fare - 50").
class Preset {
  const Preset({
    this.id,
    required this.label,
    required this.amount,
    required this.type,
    this.accountId,
    this.categoryId,
    this.note = '',
    this.sortOrder = 0,
  });

  final int? id;
  final String label;
  final double amount;
  final TxType type;
  final int? accountId;
  final int? categoryId;
  final String note;
  final int sortOrder;

  factory Preset.fromRow(Map<String, Object?> row) => Preset(
        id: row['id'] as int,
        label: row['label'] as String,
        amount: (row['amount'] as num).toDouble(),
        type: TxType.parse(row['type'] as String),
        accountId: (row['account_id'] as num?)?.toInt(),
        categoryId: (row['category_id'] as num?)?.toInt(),
        note: (row['note'] as String?) ?? '',
        sortOrder: (row['sort_order'] as num).toInt(),
      );

  Preset copyWith({
    String? label,
    double? amount,
    TxType? type,
    int? accountId,
    int? categoryId,
    String? note,
    int? sortOrder,
  }) =>
      Preset(
        id: id,
        label: label ?? this.label,
        amount: amount ?? this.amount,
        type: type ?? this.type,
        accountId: accountId ?? this.accountId,
        categoryId: categoryId ?? this.categoryId,
        note: note ?? this.note,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}
