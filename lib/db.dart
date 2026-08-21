import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import 'constants.dart';
import 'models.dart';

/// Must run before any `sqlite3.open`. Linux must use the SQLite compiled into
/// `libsqlite3_flutter_libs_plugin.so`, not Kali's `libsqlite3.so.0` — mixing
/// those ABIs segfaults (call to NULL).
void configureSqliteLoader() {
  if (AppDatabase._loaderConfigured) return;
  AppDatabase._loaderConfigured = true;
  if (Platform.isLinux) {
    sqlite_open.open.overrideFor(
      sqlite_open.OperatingSystem.linux,
      _openBundledSqlite,
    );
  } else if (Platform.isWindows) {
    sqlite_open.open.overrideFor(
      sqlite_open.OperatingSystem.windows,
      _openWindowsSqlite,
    );
  }
}

DynamicLibrary _openBundledSqlite() {
  final String exeDir = File(Platform.resolvedExecutable).parent.path;
  final List<String> candidates = <String>[
    p.join(exeDir, 'lib', 'libsqlite3_flutter_libs_plugin.so'),
    p.join(exeDir, 'libsqlite3_flutter_libs_plugin.so'),
    'libsqlite3_flutter_libs_plugin.so',
  ];
  Object? lastError;
  for (final String path in candidates) {
    try {
      return DynamicLibrary.open(path);
    } catch (error) {
      lastError = error;
    }
  }
  throw StateError('Could not load bundled SQLite: $lastError');
}

/// sqlite3_flutter_libs copies sqlite3.dll next to the .exe on Windows.
DynamicLibrary _openWindowsSqlite() {
  final String exeDir = File(Platform.resolvedExecutable).parent.path;
  final List<String> candidates = <String>[
    p.join(exeDir, 'sqlite3.dll'),
    'sqlite3.dll',
  ];
  Object? lastError;
  for (final String path in candidates) {
    try {
      return DynamicLibrary.open(path);
    } catch (error) {
      lastError = error;
    }
  }
  throw StateError('Could not load sqlite3.dll: $lastError');
}

/// Everything that touches SQLite lives here. Calls are synchronous, which is
/// fine for a single-user local database of a few thousand rows.
class AppDatabase {
  AppDatabase._(this._db, this.filePath);

  Database _db;
  final String filePath;

  static bool _loaderConfigured = false;

  /// Opens (creating on first run) the database in the platform app-support
  /// directory, e.g. `~/.local/share/com.dailyledger.dailyledger/` on Linux.
  static Future<AppDatabase> open() async {
    configureSqliteLoader();
    await _configureAndroidLoader();
    final Directory dir = await getApplicationSupportDirectory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final String path = p.join(dir.path, kDbFileName);
    final Database db = sqlite3.open(path);
    db.execute('PRAGMA foreign_keys = ON;');
    final AppDatabase instance = AppDatabase._(db, path);
    instance._migrate();
    instance.recomputeBalances();
    return instance;
  }

  static Future<void> _configureAndroidLoader() async {
    if (!Platform.isAndroid) return;
    await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    sqlite_open.open.overrideFor(
      sqlite_open.OperatingSystem.android,
      () => DynamicLibrary.open('libsqlite3.so'),
    );
  }

  void close() => _db.dispose();

  /// Consistent snapshot, even while the live database is open.
  void writeCopy(String destPath) {
    final File dest = File(destPath);
    if (dest.existsSync()) dest.deleteSync();
    final String escaped = destPath.replaceAll("'", "''");
    _db.execute("VACUUM INTO '$escaped'");
  }

  /// Closes the live file, overwrites it, and reopens. [backupPath] must not
  /// be the live path.
  Future<void> replaceFrom(String backupPath) async {
    assertValidBackup(backupPath);
    if (p.normalize(backupPath) == p.normalize(filePath)) {
      throw StateError('Pick a backup file, not the live database.');
    }
    _db.dispose();
    await File(backupPath).copy(filePath);
    _db = sqlite3.open(filePath);
    _db.execute('PRAGMA foreign_keys = ON;');
    _migrate();
    recomputeBalances();
  }

  static void assertValidBackup(String path) {
    final File file = File(path);
    if (!file.existsSync() || file.lengthSync() < 100) {
      throw StateError('That file is not a DailyLedger backup.');
    }
    final RandomAccessFile raf = file.openSync();
    final List<int> header = raf.readSync(16);
    raf.closeSync();
    if (String.fromCharCodes(header.take(15)) != 'SQLite format 3') {
      throw StateError('That file is not a DailyLedger backup.');
    }
    final Database probe = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      probe.select('SELECT COUNT(*) FROM sqlite_master WHERE name = ?', <Object?>['accounts']);
      probe.select('SELECT COUNT(*) FROM accounts');
      probe.select('SELECT COUNT(*) FROM transactions');
    } catch (_) {
      probe.dispose();
      throw StateError('That file is not a DailyLedger backup.');
    }
    probe.dispose();
  }

  int transactionCount() => (_db
          .select('SELECT COUNT(*) AS c FROM transactions')
          .first['c'] as num)
      .toInt();

  // -------------------------------------------------------------------------
  // Schema
  // -------------------------------------------------------------------------

  static const int _schemaVersion = 3;

  static const List<String> _schema = <String>[
    '''
    CREATE TABLE accounts (
      id               INTEGER PRIMARY KEY AUTOINCREMENT,
      name             TEXT    NOT NULL,
      starting_balance REAL    NOT NULL DEFAULT 0,
      current_balance  REAL    NOT NULL DEFAULT 0,
      sort_order       INTEGER NOT NULL DEFAULT 0
    )''',
    '''
    CREATE TABLE categories (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      name       TEXT    NOT NULL,
      type       TEXT    NOT NULL CHECK (type IN ('expense', 'income')),
      icon       TEXT,
      sort_order INTEGER NOT NULL DEFAULT 0
    )''',
    '''
    CREATE TABLE transactions (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      amount        REAL    NOT NULL CHECK (amount >= 0),
      type          TEXT    NOT NULL CHECK (type IN ('expense', 'income', 'transfer', 'lend', 'borrow')),
      account_id    INTEGER NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
      to_account_id INTEGER REFERENCES accounts(id) ON DELETE RESTRICT,
      category_id   INTEGER REFERENCES categories(id) ON DELETE SET NULL,
      date          TEXT    NOT NULL,
      note          TEXT    NOT NULL DEFAULT '',
      person        TEXT    NOT NULL DEFAULT '',
      is_recurring  INTEGER NOT NULL DEFAULT 0,
      in_kind       INTEGER NOT NULL DEFAULT 0,
      is_settlement INTEGER NOT NULL DEFAULT 0
    )''',
    'CREATE INDEX idx_transactions_date ON transactions(date)',
    '''
    CREATE TABLE recurring_rules (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      amount        REAL    NOT NULL,
      type          TEXT    NOT NULL CHECK (type IN ('expense', 'income')),
      account_id    INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
      category_id   INTEGER REFERENCES categories(id) ON DELETE SET NULL,
      note          TEXT    NOT NULL DEFAULT '',
      frequency     TEXT    NOT NULL DEFAULT 'monthly',
      day_of_month  INTEGER NOT NULL DEFAULT 1,
      next_due_date TEXT    NOT NULL,
      active        INTEGER NOT NULL DEFAULT 1
    )''',
    '''
    CREATE TABLE budgets (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      category_id   INTEGER UNIQUE REFERENCES categories(id) ON DELETE CASCADE,
      monthly_limit REAL    NOT NULL
    )''',
    '''
    CREATE TABLE presets (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      label       TEXT    NOT NULL,
      amount      REAL    NOT NULL,
      type        TEXT    NOT NULL CHECK (type IN ('expense', 'income')),
      account_id  INTEGER REFERENCES accounts(id) ON DELETE SET NULL,
      category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
      note        TEXT    NOT NULL DEFAULT '',
      sort_order  INTEGER NOT NULL DEFAULT 0
    )''',
  ];

  void _migrate() {
    final int version =
        (_db.select('PRAGMA user_version').first['user_version'] as num).toInt();
    if (version >= _schemaVersion) return;
    _db.execute('BEGIN');
    try {
      if (version == 0) {
        for (final String statement in _schema) {
          _db.execute(statement);
        }
        _seed();
      } else {
        if (version < 2) _migrateToV2();
        if (version < 3) _migrateToV3();
      }
      _db.execute('PRAGMA user_version = $_schemaVersion');
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// v1 → v2: lend/borrow types plus a person name on IOU rows.
  void _migrateToV2() {
    _db.execute('''
      CREATE TABLE transactions_new (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        amount        REAL    NOT NULL CHECK (amount >= 0),
        type          TEXT    NOT NULL CHECK (type IN ('expense', 'income', 'transfer', 'lend', 'borrow')),
        account_id    INTEGER NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
        to_account_id INTEGER REFERENCES accounts(id) ON DELETE RESTRICT,
        category_id   INTEGER REFERENCES categories(id) ON DELETE SET NULL,
        date          TEXT    NOT NULL,
        note          TEXT    NOT NULL DEFAULT '',
        person        TEXT    NOT NULL DEFAULT '',
        is_recurring  INTEGER NOT NULL DEFAULT 0
      )
    ''');
    _db.execute('''
      INSERT INTO transactions_new
        (id, amount, type, account_id, to_account_id, category_id, date, note, person, is_recurring)
      SELECT id, amount, type, account_id, to_account_id, category_id, date, note, '', is_recurring
      FROM transactions
    ''');
    _db.execute('DROP TABLE transactions');
    _db.execute('ALTER TABLE transactions_new RENAME TO transactions');
    _db.execute('CREATE INDEX idx_transactions_date ON transactions(date)');
  }

  /// v2 → v3: goods/tab IOUs (no cash yet) and settle rows.
  void _migrateToV3() {
    _db.execute(
      'ALTER TABLE transactions ADD COLUMN in_kind INTEGER NOT NULL DEFAULT 0',
    );
    _db.execute(
      'ALTER TABLE transactions ADD COLUMN is_settlement INTEGER NOT NULL DEFAULT 0',
    );
  }

  /// First-launch data: two accounts, boarding/uni categories, two presets.
  void _seed() {
    _db.execute(
      'INSERT INTO accounts (name, starting_balance, current_balance, sort_order) '
      "VALUES ('Cash', 0, 0, 0), ('Bank Card', 0, 0, 1)",
    );

    const List<List<String>> expenseCategories = <List<String>>[
      <String>['Food', 'restaurant'],
      <String>['Groceries', 'shopping_cart'],
      <String>['Boarding/Rent', 'home'],
      <String>['Transport', 'directions_bus'],
      <String>['Mobile/Data', 'sim_card'],
      <String>['Education', 'school'],
      <String>['Entertainment', 'movie'],
      <String>['Savings', 'savings'],
      <String>['Other', 'category'],
    ];
    const List<List<String>> incomeCategories = <List<String>>[
      <String>['Allowance', 'payments'],
      <String>['Part-time', 'work'],
      <String>['Gift', 'card_giftcard'],
      <String>['Other income', 'category'],
    ];

    int order = 0;
    for (final List<String> c in expenseCategories) {
      _db.execute(
        'INSERT INTO categories (name, type, icon, sort_order) VALUES (?, ?, ?, ?)',
        <Object?>[c[0], 'expense', c[1], order++],
      );
    }
    for (final List<String> c in incomeCategories) {
      _db.execute(
        'INSERT INTO categories (name, type, icon, sort_order) VALUES (?, ?, ?, ?)',
        <Object?>[c[0], 'income', c[1], order++],
      );
    }

    final int cashId =
        (_db.select("SELECT id FROM accounts WHERE name = 'Cash'").first['id']
                as num)
            .toInt();
    final int transportId = (_db
            .select("SELECT id FROM categories WHERE name = 'Transport'")
            .first['id'] as num)
        .toInt();
    final int foodId = (_db
            .select("SELECT id FROM categories WHERE name = 'Food'")
            .first['id'] as num)
        .toInt();

    _db.execute(
      'INSERT INTO presets (label, amount, type, account_id, category_id, note, sort_order) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      <Object?>['Bus fare', 50.0, 'expense', cashId, transportId, 'Bus fare', 0],
    );
    _db.execute(
      'INSERT INTO presets (label, amount, type, account_id, category_id, note, sort_order) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      <Object?>['Tea', 40.0, 'expense', cashId, foodId, 'Tea', 1],
    );
  }

  // -------------------------------------------------------------------------
  // Accounts
  // -------------------------------------------------------------------------

  List<Account> accounts() => _db
      .select('''
        SELECT accounts.*,
          accounts.starting_balance
            + COALESCE((
                SELECT SUM(CASE t.type
                  WHEN 'income' THEN t.amount
                  WHEN 'expense' THEN -t.amount
                  WHEN 'transfer' THEN -t.amount
                  ELSE 0
                END)
                FROM transactions t WHERE t.account_id = accounts.id
              ), 0)
            + COALESCE((
                SELECT SUM(t.amount) FROM transactions t
                WHERE t.to_account_id = accounts.id AND t.type = 'transfer'
              ), 0) AS own_balance
        FROM accounts
        ORDER BY sort_order, id
      ''')
      .map((Row r) => Account.fromRow(r))
      .toList();

  int insertAccount(Account account) {
    _db.execute(
      'INSERT INTO accounts (name, starting_balance, current_balance, sort_order) '
      'VALUES (?, ?, ?, ?)',
      <Object?>[
        account.name,
        account.startingBalance,
        account.startingBalance,
        account.sortOrder,
      ],
    );
    return _db.lastInsertRowId;
  }

  void updateAccount(Account account) => _db.execute(
        'UPDATE accounts SET name = ?, starting_balance = ?, sort_order = ? WHERE id = ?',
        <Object?>[
          account.name,
          account.startingBalance,
          account.sortOrder,
          account.id,
        ],
      );

  void deleteAccount(int id) =>
      _db.execute('DELETE FROM accounts WHERE id = ?', <Object?>[id]);

  int transactionCountForAccount(int id) => (_db.select(
        'SELECT COUNT(*) AS c FROM transactions WHERE account_id = ? OR to_account_id = ?',
        <Object?>[id, id],
      ).first['c'] as num)
          .toInt();

  /// `current_balance` is derived, never edited directly: recompute it from the
  /// transaction table so the two can never disagree.
  void recomputeBalances() => _db.execute('''
      UPDATE accounts SET current_balance = starting_balance
        + COALESCE((
            SELECT SUM(CASE t.type
              WHEN 'income' THEN t.amount
              WHEN 'expense' THEN -t.amount
              WHEN 'transfer' THEN -t.amount
              WHEN 'borrow' THEN CASE WHEN t.in_kind = 1 THEN 0 ELSE t.amount END
              WHEN 'lend' THEN CASE WHEN t.in_kind = 1 THEN 0 ELSE -t.amount END
              ELSE 0
            END)
            FROM transactions t WHERE t.account_id = accounts.id
          ), 0)
        + COALESCE((
            SELECT SUM(t.amount) FROM transactions t
            WHERE t.to_account_id = accounts.id AND t.type = 'transfer'
          ), 0)
      ''');

  // -------------------------------------------------------------------------
  // Categories
  // -------------------------------------------------------------------------

  List<Category> categories() => _db
      .select('SELECT * FROM categories ORDER BY sort_order, id')
      .map((Row r) => Category.fromRow(r))
      .toList();

  int insertCategory(Category category) {
    _db.execute(
      'INSERT INTO categories (name, type, icon, sort_order) VALUES (?, ?, ?, ?)',
      <Object?>[
        category.name,
        category.type.name,
        category.iconKey,
        category.sortOrder,
      ],
    );
    return _db.lastInsertRowId;
  }

  void updateCategory(Category category) => _db.execute(
        'UPDATE categories SET name = ?, type = ?, icon = ?, sort_order = ? WHERE id = ?',
        <Object?>[
          category.name,
          category.type.name,
          category.iconKey,
          category.sortOrder,
          category.id,
        ],
      );

  /// Transactions keep their history and fall back to "Uncategorised".
  void deleteCategory(int id) =>
      _db.execute('DELETE FROM categories WHERE id = ?', <Object?>[id]);

  // -------------------------------------------------------------------------
  // Transactions
  // -------------------------------------------------------------------------

  List<Txn> transactions({
    DateTime? from,
    DateTime? to,
    int? categoryId,
    int? accountId,
    TxType? type,
    String? search,
    int? limit,
  }) {
    final List<String> where = <String>[];
    final List<Object?> args = <Object?>[];
    if (from != null) {
      where.add('date >= ?');
      args.add(isoDate(from));
    }
    if (to != null) {
      where.add('date <= ?');
      args.add(isoDate(to));
    }
    if (categoryId != null) {
      where.add('category_id = ?');
      args.add(categoryId);
    }
    if (accountId != null) {
      where.add('(account_id = ? OR to_account_id = ?)');
      args..add(accountId)..add(accountId);
    }
    if (type != null) {
      where.add('type = ?');
      args.add(type.name);
    }
    if (search != null && search.trim().isNotEmpty) {
      where.add('(note LIKE ? OR person LIKE ?)');
      args..add('%${search.trim()}%')..add('%${search.trim()}%');
    }
    final String clause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final String limitClause = limit == null ? '' : 'LIMIT $limit';
    return _db
        .select(
          'SELECT * FROM transactions $clause ORDER BY date DESC, id DESC $limitClause',
          args,
        )
        .map((Row r) => Txn.fromRow(r))
        .toList();
  }

  int insertTransaction(Txn txn) {
    _db.execute(
      'INSERT INTO transactions '
      '(amount, type, account_id, to_account_id, category_id, date, note, person, '
      'is_recurring, in_kind, is_settlement) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        txn.amount,
        txn.type.name,
        txn.accountId,
        txn.toAccountId,
        txn.categoryId,
        isoDate(txn.date),
        txn.note,
        txn.person,
        txn.isRecurring ? 1 : 0,
        txn.inKind ? 1 : 0,
        txn.isSettlement ? 1 : 0,
      ],
    );
    return _db.lastInsertRowId;
  }

  void updateTransaction(Txn txn) => _db.execute(
        'UPDATE transactions SET amount = ?, type = ?, account_id = ?, '
        'to_account_id = ?, category_id = ?, date = ?, note = ?, person = ?, '
        'is_recurring = ?, in_kind = ?, is_settlement = ? WHERE id = ?',
        <Object?>[
          txn.amount,
          txn.type.name,
          txn.accountId,
          txn.toAccountId,
          txn.categoryId,
          isoDate(txn.date),
          txn.note,
          txn.person,
          txn.isRecurring ? 1 : 0,
          txn.inKind ? 1 : 0,
          txn.isSettlement ? 1 : 0,
          txn.id,
        ],
      );

  void deleteTransaction(int id) =>
      _db.execute('DELETE FROM transactions WHERE id = ?', <Object?>[id]);

  /// Totals per transaction type inside a date range.
  Map<TxType, double> totalsByType(DateTime from, DateTime to) {
    final Map<TxType, double> result = <TxType, double>{};
    for (final Row row in _db.select(
      'SELECT type, SUM(amount) AS total FROM transactions '
      'WHERE date >= ? AND date <= ? AND is_settlement = 0 GROUP BY type',
      <Object?>[isoDate(from), isoDate(to)],
    )) {
      result[TxType.parse(row['type'] as String)] =
          (row['total'] as num).toDouble();
    }
    return result;
  }

  /// Net IOU per person. Empty names are shown as "Someone".
  List<PersonBalance> personBalances() {
    final Map<String, PersonBalance> byName = <String, PersonBalance>{};
    for (final Row row in _db.select(
      '''
      SELECT person, type, SUM(amount) AS total FROM transactions
      WHERE type IN ('lend', 'borrow')
      GROUP BY person, type
      ''',
    )) {
      final String name = (row['person'] as String?)?.trim() ?? '';
      final String key = name.isEmpty ? 'Someone' : name;
      final TxType type = TxType.parse(row['type'] as String);
      final double total = (row['total'] as num).toDouble();
      final PersonBalance current = byName[key] ??
          PersonBalance(name: key, lent: 0, borrowed: 0);
      byName[key] = PersonBalance(
        name: key,
        lent: current.lent + (type == TxType.lend ? total : 0),
        borrowed: current.borrowed + (type == TxType.borrow ? total : 0),
      );
    }
    final List<PersonBalance> list = byName.values.toList()
      ..sort((PersonBalance a, PersonBalance b) {
        final int byAbs = b.net.abs().compareTo(a.net.abs());
        if (byAbs != 0) return byAbs;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return list;
  }

  /// Account used on the latest lend/borrow for this person, if any.
  int? lastAccountIdForPerson(String name) {
    final ResultSet rows = _db.select(
      '''
      SELECT account_id FROM transactions
      WHERE type IN ('lend', 'borrow') AND TRIM(person) = ?
      ORDER BY date DESC, id DESC LIMIT 1
      ''',
      <Object?>[name.trim()],
    );
    if (rows.isEmpty) return null;
    return (rows.first['account_id'] as num).toInt();
  }

  /// Expense totals per category inside a date range (`null` key = no category).
  Map<int?, double> expenseByCategory(DateTime from, DateTime to) {
    final Map<int?, double> result = <int?, double>{};
    for (final Row row in _db.select(
      '''
      SELECT category_id, SUM(amount) AS total FROM transactions
      WHERE type = 'expense' AND date >= ? AND date <= ? GROUP BY category_id
      ''',
      <Object?>[isoDate(from), isoDate(to)],
    )) {
      result[(row['category_id'] as num?)?.toInt()] =
          (row['total'] as num).toDouble();
    }
    return result;
  }

  // -------------------------------------------------------------------------
  // Recurring rules
  // -------------------------------------------------------------------------

  List<RecurringRule> recurringRules() => _db
      .select('SELECT * FROM recurring_rules ORDER BY next_due_date, id')
      .map((Row r) => RecurringRule.fromRow(r))
      .toList();

  int insertRecurringRule(RecurringRule rule) {
    _db.execute(
      'INSERT INTO recurring_rules '
      '(amount, type, account_id, category_id, note, frequency, day_of_month, next_due_date, active) '
      "VALUES (?, ?, ?, ?, ?, 'monthly', ?, ?, ?)",
      <Object?>[
        rule.amount,
        rule.type.name,
        rule.accountId,
        rule.categoryId,
        rule.note,
        rule.dayOfMonth,
        isoDate(rule.nextDueDate),
        rule.active ? 1 : 0,
      ],
    );
    return _db.lastInsertRowId;
  }

  void updateRecurringRule(RecurringRule rule) => _db.execute(
        'UPDATE recurring_rules SET amount = ?, type = ?, account_id = ?, '
        'category_id = ?, note = ?, day_of_month = ?, next_due_date = ?, active = ? '
        'WHERE id = ?',
        <Object?>[
          rule.amount,
          rule.type.name,
          rule.accountId,
          rule.categoryId,
          rule.note,
          rule.dayOfMonth,
          isoDate(rule.nextDueDate),
          rule.active ? 1 : 0,
          rule.id,
        ],
      );

  void deleteRecurringRule(int id) =>
      _db.execute('DELETE FROM recurring_rules WHERE id = ?', <Object?>[id]);

  // -------------------------------------------------------------------------
  // Budgets
  // -------------------------------------------------------------------------

  List<Budget> budgets() => _db
      .select('SELECT * FROM budgets')
      .map((Row r) => Budget.fromRow(r))
      .toList();

  /// One row per category (plus one row with a null category for the overall
  /// limit). Writing 0 or less removes the limit.
  void setBudget(int? categoryId, double monthlyLimit) {
    if (monthlyLimit <= 0) {
      clearBudget(categoryId);
      return;
    }
    if (categoryId == null) {
      final ResultSet existing =
          _db.select('SELECT id FROM budgets WHERE category_id IS NULL');
      if (existing.isEmpty) {
        _db.execute(
          'INSERT INTO budgets (category_id, monthly_limit) VALUES (NULL, ?)',
          <Object?>[monthlyLimit],
        );
      } else {
        _db.execute(
          'UPDATE budgets SET monthly_limit = ? WHERE category_id IS NULL',
          <Object?>[monthlyLimit],
        );
      }
      return;
    }
    _db.execute(
      'INSERT INTO budgets (category_id, monthly_limit) VALUES (?, ?) '
      'ON CONFLICT(category_id) DO UPDATE SET monthly_limit = excluded.monthly_limit',
      <Object?>[categoryId, monthlyLimit],
    );
  }

  void clearBudget(int? categoryId) {
    if (categoryId == null) {
      _db.execute('DELETE FROM budgets WHERE category_id IS NULL');
    } else {
      _db.execute(
        'DELETE FROM budgets WHERE category_id = ?',
        <Object?>[categoryId],
      );
    }
  }

  // -------------------------------------------------------------------------
  // Quick-add presets
  // -------------------------------------------------------------------------

  List<Preset> presets() => _db
      .select('SELECT * FROM presets ORDER BY sort_order, id')
      .map((Row r) => Preset.fromRow(r))
      .toList();

  int insertPreset(Preset preset) {
    _db.execute(
      'INSERT INTO presets (label, amount, type, account_id, category_id, note, sort_order) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        preset.label,
        preset.amount,
        preset.type.name,
        preset.accountId,
        preset.categoryId,
        preset.note,
        preset.sortOrder,
      ],
    );
    return _db.lastInsertRowId;
  }

  void updatePreset(Preset preset) => _db.execute(
        'UPDATE presets SET label = ?, amount = ?, type = ?, account_id = ?, '
        'category_id = ?, note = ?, sort_order = ? WHERE id = ?',
        <Object?>[
          preset.label,
          preset.amount,
          preset.type.name,
          preset.accountId,
          preset.categoryId,
          preset.note,
          preset.sortOrder,
          preset.id,
        ],
      );

  void deletePreset(int id) =>
      _db.execute('DELETE FROM presets WHERE id = ?', <Object?>[id]);

  // -------------------------------------------------------------------------
  // Export
  // -------------------------------------------------------------------------

  /// Flat rows with resolved account/category names, ready for CSV.
  List<List<Object?>> exportRows() => _db
      .select('''
        SELECT t.id, t.date, t.type, t.amount,
               a.name  AS account,
               a2.name AS to_account,
               c.name  AS category,
               t.person, t.note, t.is_recurring, t.in_kind, t.is_settlement
        FROM transactions t
        LEFT JOIN accounts   a  ON a.id  = t.account_id
        LEFT JOIN accounts   a2 ON a2.id = t.to_account_id
        LEFT JOIN categories c  ON c.id  = t.category_id
        ORDER BY t.date, t.id
      ''')
      .map(
        (Row r) => <Object?>[
          r['id'],
          r['date'],
          r['type'],
          r['amount'],
          r['account'],
          r['to_account'],
          r['category'],
          r['person'],
          r['note'],
          (r['is_recurring'] as num).toInt() == 1 ? 'yes' : 'no',
          (r['in_kind'] as num?)?.toInt() == 1 ? 'yes' : 'no',
          (r['is_settlement'] as num?)?.toInt() == 1 ? 'yes' : 'no',
        ],
      )
      .toList();

  static const List<String> exportHeader = <String>[
    'id',
    'date',
    'type',
    'amount',
    'account',
    'to_account',
    'category',
    'person',
    'note',
    'is_recurring',
    'in_kind',
    'is_settlement',
  ];
}
