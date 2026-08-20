import 'package:flutter_test/flutter_test.dart';

import 'package:dailyledger/cloud_sync.dart';
import 'package:dailyledger/constants.dart';
import 'package:dailyledger/models.dart';

void main() {
  test('formatMoney groups thousands and keeps two decimals', () {
    expect(formatMoney(1234.5), 'Rs 1,234.50');
    expect(formatMoney(-40), '-Rs 40.00');
    expect(formatMoney(50, withSymbol: false), '50.00');
  });

  test('isoDate round-trips as YYYY-MM-DD', () {
    expect(isoDate(DateTime(2026, 8, 20)), '2026-08-20');
    expect(parseIsoDate('2026-08-20'), DateTime(2026, 8, 20));
  });

  test('lend leaves your pocket, borrow arrives, neither is a transfer', () {
    final Txn lent = Txn(
      amount: 200,
      type: TxType.lend,
      accountId: 1,
      date: DateTime(2026, 8, 20),
      person: 'Rahul',
    );
    final Txn borrowed = Txn(
      amount: 150,
      type: TxType.borrow,
      accountId: 1,
      date: DateTime(2026, 8, 20),
      person: 'Amal',
    );
    expect(lent.signedAmount, -200);
    expect(borrowed.signedAmount, 150);
    expect(TxType.parse('lend'), TxType.lend);
    expect(TxType.parse('borrow'), TxType.borrow);
    expect(TxType.lend.usesPerson, isTrue);
    expect(TxType.borrow.usesCategory, isFalse);
  });

  test('person IOU nets lend against borrow', () {
    const PersonBalance both = PersonBalance(
      name: 'Rahul',
      lent: 500,
      borrowed: 200,
    );
    expect(both.net, 300);
  });

  test('cloud slot URL points at one Firebase node', () {
    expect(
      cloudSlotUrl(
        'https://demo-default-rtdb.asia-southeast1.firebasedatabase.app/',
        'ab12-cd34',
      ),
      'https://demo-default-rtdb.asia-southeast1.firebasedatabase.app/dailyledger/AB12CD34.json',
    );
    expect(formatSyncCode('ab12cd34'), 'AB12-CD34');
  });

  test('recurring next due is today or later', () {
    final DateTime due = RecurringRule.nextDueForDay(1, from: DateTime(2026, 8, 20));
    expect(due, DateTime(2026, 9, 1));
  });
}
