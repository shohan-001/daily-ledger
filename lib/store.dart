import 'package:flutter/foundation.dart' hide Category;

import 'constants.dart';
import 'db.dart';
import 'models.dart';

/// The only piece of state in the app. Screens read the cached lists below and
/// call the mutating methods, which write to SQLite and reload the caches.
class AppStore extends ChangeNotifier {
  AppStore(this._db);

  final AppDatabase _db;

  AppDatabase get db => _db;

  List<Account> accounts = const <Account>[];
  List<Category> categories = const <Category>[];
  List<Preset> presets = const <Preset>[];
  List<RecurringRule> rules = const <RecurringRule>[];
  List<Budget> budgets = const <Budget>[];
  List<Txn> recent = const <Txn>[];

  /// Expense totals for [month], keyed by category id (`null` = uncategorised).
  Map<int?, double> spentByCategory = const <int?, double>{};
  double monthExpense = 0;
  double monthIncome = 0;
  double monthLent = 0;
  double monthBorrowed = 0;
  List<PersonBalance> people = const <PersonBalance>[];

  /// The month the dashboard and budgets screen are looking at.
  DateTime month = monthStart(DateTime.now());

  void reload() {
    accounts = _db.accounts();
    categories = _db.categories();
    presets = _db.presets();
    rules = _db.recurringRules();
    budgets = _db.budgets();
    recent = _db.transactions(limit: kRecentTransactionCount);

    final DateTime from = monthStart(month);
    final DateTime to = monthEnd(month);
    spentByCategory = _db.expenseByCategory(from, to);
    final Map<TxType, double> totals = _db.totalsByType(from, to);
    monthExpense = (totals[TxType.expense] ?? 0) + _db.settlementPaid(from, to);
    monthIncome = totals[TxType.income] ?? 0;
    monthLent = totals[TxType.lend] ?? 0;
    monthBorrowed = totals[TxType.borrow] ?? 0;
    people = _db.personBalances();

    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Lookups
  // -------------------------------------------------------------------------

  Account? accountById(int? id) {
    if (id == null) return null;
    for (final Account a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  Category? categoryById(int? id) {
    if (id == null) return null;
    for (final Category c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  String accountName(int? id) => accountById(id)?.name ?? '—';

  String categoryName(int? id) => categoryById(id)?.name ?? 'Uncategorised';

  List<Category> categoriesOfType(TxType type) =>
      categories.where((Category c) => c.type == type).toList();

  double get totalBalance =>
      accounts.fold<double>(0, (double sum, Account a) => sum + a.currentBalance);

  /// Cash you actually own across accounts — lend/borrow not mixed in.
  double get ownTotal =>
      accounts.fold<double>(0, (double sum, Account a) => sum + a.ownBalance);

  double get owedToYou => people.fold<double>(
        0,
        (double sum, PersonBalance p) => sum + (p.net > 0 ? p.net : 0),
      );

  double get youOwe => people.fold<double>(
        0,
        (double sum, PersonBalance p) => sum + (p.net < 0 ? -p.net : 0),
      );

  /// Your cash plus what friends still owe, minus what you still owe.
  double get ownPlusIous => ownTotal + owedToYou - youOwe;

  Account? get cashAccount {
    for (final Account account in accounts) {
      if (account.name.trim().toLowerCase() == 'cash') return account;
    }
    return accounts.isEmpty ? null : accounts.first;
  }

  /// Overall monthly limit, or null when it has not been set.
  double? get overallLimit {
    for (final Budget b in budgets) {
      if (b.categoryId == null) return b.monthlyLimit;
    }
    return null;
  }

  double? limitForCategory(int categoryId) {
    for (final Budget b in budgets) {
      if (b.categoryId == categoryId) return b.monthlyLimit;
    }
    return null;
  }

  double spentInCategory(int categoryId) => spentByCategory[categoryId] ?? 0;

  // -------------------------------------------------------------------------
  // Month navigation
  // -------------------------------------------------------------------------

  void showMonth(DateTime value) {
    month = monthStart(value);
    reload();
  }

  void previousMonth() => showMonth(addMonths(month, -1));

  void nextMonth() => showMonth(addMonths(month, 1));

  bool get isCurrentMonth => month == monthStart(DateTime.now());

  // -------------------------------------------------------------------------
  // Transactions
  // -------------------------------------------------------------------------

  void saveTransaction(Txn txn) {
    if (txn.id == null) {
      _db.insertTransaction(txn);
    } else {
      _db.updateTransaction(txn);
    }
    _db.recomputeBalances();
    reload();
  }

  void deleteTransaction(int id) {
    _db.deleteTransaction(id);
    _db.recomputeBalances();
    reload();
  }

  /// Pay or collect the open IOU with [person]. Cash always moves.
  /// Returns the new row id so the UI can offer Undo.
  int? settlePerson(PersonBalance person, {int? accountId}) {
    final double net = person.net;
    if (net == 0) return null;
    final int? payFrom = accountId ??
        _db.lastAccountIdForPerson(person.name) ??
        cashAccount?.id;
    if (payFrom == null) return null;
    final bool theyOwe = net > 0;
    final int id = _db.insertTransaction(
      Txn(
        amount: net.abs(),
        type: theyOwe ? TxType.borrow : TxType.lend,
        accountId: payFrom,
        date: dayStart(DateTime.now()),
        note: 'Settled',
        person: person.name,
        isSettlement: true,
      ),
    );
    _db.recomputeBalances();
    reload();
    return id;
  }

  List<Txn> query({
    DateTime? from,
    DateTime? to,
    int? categoryId,
    int? accountId,
    TxType? type,
    String? search,
    int? limit,
  }) =>
      _db.transactions(
        from: from,
        to: to,
        categoryId: categoryId,
        accountId: accountId,
        type: type,
        search: search,
        limit: limit,
      );

  // -------------------------------------------------------------------------
  // Accounts / categories / budgets / presets
  // -------------------------------------------------------------------------

  void saveAccount(Account account) {
    if (account.id == null) {
      _db.insertAccount(account.copyWith(sortOrder: accounts.length));
    } else {
      _db.updateAccount(account);
    }
    _db.recomputeBalances();
    reload();
  }

  /// Returns false when the account still has transactions attached.
  bool deleteAccount(int id) {
    if (_db.transactionCountForAccount(id) > 0) return false;
    _db.deleteAccount(id);
    reload();
    return true;
  }

  void saveCategory(Category category) {
    if (category.id == null) {
      _db.insertCategory(category.copyWith(sortOrder: categories.length));
    } else {
      _db.updateCategory(category);
    }
    reload();
  }

  void deleteCategory(int id) {
    _db.deleteCategory(id);
    reload();
  }

  void setBudget(int? categoryId, double monthlyLimit) {
    _db.setBudget(categoryId, monthlyLimit);
    reload();
  }

  void clearBudget(int? categoryId) {
    _db.clearBudget(categoryId);
    reload();
  }

  void savePreset(Preset preset) {
    if (preset.id == null) {
      _db.insertPreset(preset.copyWith(sortOrder: presets.length));
    } else {
      _db.updatePreset(preset);
    }
    reload();
  }

  void deletePreset(int id) {
    _db.deletePreset(id);
    reload();
  }

  // -------------------------------------------------------------------------
  // Recurring rules
  // -------------------------------------------------------------------------

  void saveRule(RecurringRule rule) {
    if (rule.id == null) {
      _db.insertRecurringRule(rule);
    } else {
      _db.updateRecurringRule(rule);
    }
    reload();
  }

  void deleteRule(int id) {
    _db.deleteRecurringRule(id);
    reload();
  }

  /// Rules whose next due date has arrived. Checked once at launch only.
  List<RecurringRule> dueRules() {
    final DateTime today = dayStart(DateTime.now());
    return rules.where((RecurringRule r) => r.isDue(today)).toList();
  }

  /// Creates the real transaction for [rule] and moves it to the next month.
  void confirmRule(RecurringRule rule) {
    _db.insertTransaction(rule.toTransaction());
    _db.updateRecurringRule(rule.copyWith(nextDueDate: rule.advanced()));
    _db.recomputeBalances();
    reload();
  }

  /// Moves [rule] to the next month without creating a transaction.
  void skipRule(RecurringRule rule) {
    _db.updateRecurringRule(rule.copyWith(nextDueDate: rule.advanced()));
    reload();
  }

  int get transactionCount => _db.transactionCount();

  /// Replaces this device's database with [backupPath] (the whole file).
  Future<void> importBackup(String backupPath) async {
    await _db.replaceFrom(backupPath);
    reload();
  }

  void writeBackupTo(String destPath) => _db.writeCopy(destPath);
}
