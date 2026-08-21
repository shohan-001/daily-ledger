import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// App-wide constants. This is the file to edit for currency / naming changes.
// ---------------------------------------------------------------------------

const String kAppName = 'DailyLedger';
const String kAppVersion = '0.2.7';

const String kDeveloperName = 'Shohan';
const String kGitHubProfileUrl = 'https://github.com/shohan-001';
const String kRepoUrl = 'https://github.com/shohan-001/daily-ledger';
const String kRepoCloneUrl = 'https://github.com/shohan-001/daily-ledger.git';

/// The one and only currency. Single-currency by design; change this line only.
const String kCurrencySymbol = 'Rs';

/// File name of the SQLite database inside the platform app-support directory.
const String kDbFileName = 'dailyledger.db';

/// Local Wi-Fi backup transfer. Not exposed to the internet.
const int kSyncPort = 17890;

/// How many transactions the dashboard shows.
const int kRecentTransactionCount = 10;

/// Phone OS only — never used to shrink the Linux desktop window.
bool get kIsMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Tighter padding on a phone; desktop stays at 24.
EdgeInsets pagePadding() => EdgeInsets.all(kIsMobile ? 16 : 24);

// ---------------------------------------------------------------------------
// Palette: near-black, one accent colour, no gradients.
// ---------------------------------------------------------------------------

const Color kBackground = Color(0xFF0E0F11);
const Color kSurface = Color(0xFF16181B);
const Color kSurfaceAlt = Color(0xFF1E2126);
const Color kBorder = Color(0xFF2A2E34);
const Color kAccent = Color(0xFF4ADE80);
const Color kAccentFaint = Color(0x334ADE80);
const Color kExpense = Color(0xFFF87171);
const Color kExpenseFaint = Color(0x33F87171);
const Color kTransfer = Color(0xFF7DD3FC);
const Color kLend = Color(0xFFFBBF24);
const Color kBorrow = Color(0xFFA78BFA);
const Color kText = Color(0xFFE6E8EA);
const Color kTextMuted = Color(0xFF8A9099);

ThemeData buildTheme() {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: kAccent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: kAccent,
    onPrimary: Colors.black,
    secondary: kAccent,
    onSecondary: Colors.black,
    surface: kSurface,
    onSurface: kText,
    error: kExpense,
    onError: Colors.black,
  );

  // Only long-lived ThemeData fields are set here on purpose: the per-widget
  // sub-themes (CardTheme, InputDecorationTheme, ...) have churned across
  // Flutter versions, so widgets style themselves explicitly instead.
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBackground,
    canvasColor: kBackground,
    dividerColor: kBorder,
    visualDensity:
        kIsMobile ? VisualDensity.standard : VisualDensity.compact,
  );
}

/// Shared decoration so every text field looks the same without a sub-theme.
InputDecoration fieldDecoration(
  String label, {
  String? hint,
  String? prefixText,
  Widget? suffix,
}) {
  const OutlineInputBorder border = OutlineInputBorder(
    borderSide: BorderSide(color: kBorder),
    borderRadius: BorderRadius.all(Radius.circular(8)),
  );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixText: prefixText,
    suffixIcon: suffix,
    filled: true,
    fillColor: kSurfaceAlt,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    border: border,
    enabledBorder: border,
    focusedBorder: const OutlineInputBorder(
      borderSide: BorderSide(color: kAccent),
      borderRadius: BorderRadius.all(Radius.circular(8)),
    ),
  );
}

// ---------------------------------------------------------------------------
// Formatting helpers (hand-rolled to avoid pulling in intl + its locale data).
// ---------------------------------------------------------------------------

const List<String> _monthNames = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> _monthShort = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `1234.5` -> `Rs 1,234.50`
String formatMoney(double value, {bool withSymbol = true, bool signed = false}) {
  final bool negative = value < 0;
  final List<String> parts = value.abs().toStringAsFixed(2).split('.');
  final String digits = parts[0];
  final StringBuffer grouped = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  final String sign = negative ? '-' : (signed ? '+' : '');
  final String symbol = withSymbol ? '$kCurrencySymbol ' : '';
  return '$sign$symbol$grouped.${parts[1]}';
}

/// Storage format for dates: `YYYY-MM-DD`, so string comparison sorts by date.
String isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime parseIsoDate(String value) {
  final List<String> p = value.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// `19 Aug 2026`
String formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')} '
    '${_monthShort[date.month - 1]} ${date.year}';

/// `August 2026`
String formatMonth(DateTime date) =>
    '${_monthNames[date.month - 1]} ${date.year}';

/// Human label for a date relative to today, used in list headers.
String formatDateHeader(DateTime date) {
  final DateTime today = dayStart(DateTime.now());
  final int diff = dayStart(date).difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == -1) return 'Yesterday';
  if (diff == 1) return 'Tomorrow';
  return formatDate(date);
}

DateTime dayStart(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime monthStart(DateTime date) => DateTime(date.year, date.month);

DateTime monthEnd(DateTime date) => DateTime(date.year, date.month + 1, 0);

DateTime addMonths(DateTime date, int months) {
  final int total = date.month - 1 + months;
  final int year = date.year + (total ~/ 12);
  final int month = total % 12 + 1;
  final int lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, date.day > lastDay ? lastDay : date.day);
}

// ---------------------------------------------------------------------------
// Category icons: keys are stored in the database, values come from Flutter's
// built-in Material icon set (no icon packs).
// ---------------------------------------------------------------------------

const Map<String, IconData> kCategoryIcons = <String, IconData>{
  'restaurant': Icons.restaurant,
  'local_cafe': Icons.local_cafe,
  'shopping_cart': Icons.shopping_cart,
  'home': Icons.home,
  'directions_bus': Icons.directions_bus,
  'sim_card': Icons.sim_card,
  'school': Icons.school,
  'movie': Icons.movie,
  'savings': Icons.savings,
  'medical_services': Icons.medical_services,
  'bolt': Icons.bolt,
  'wifi': Icons.wifi,
  'fitness_center': Icons.fitness_center,
  'book': Icons.book,
  'card_giftcard': Icons.card_giftcard,
  'payments': Icons.payments,
  'work': Icons.work,
  'category': Icons.category,
};

IconData iconForKey(String? key) => kCategoryIcons[key] ?? Icons.category;

/// Colours used for the hand-rolled category chart, in order.
const List<Color> kChartColors = <Color>[
  Color(0xFF4ADE80),
  Color(0xFF60A5FA),
  Color(0xFFF87171),
  Color(0xFFFBBF24),
  Color(0xFFA78BFA),
  Color(0xFF2DD4BF),
  Color(0xFFF472B6),
  Color(0xFF94A3B8),
];
