import 'package:flutter_test/flutter_test.dart';
import 'package:vodafone_cash_tracker/models/retailer.dart';

void main() {
  group('Retailer', () {
    test('fromMap defaults credit to zero', () {
      final retailer = Retailer.fromMap({'name': 'Test', 'phone': '123'});
      expect(retailer.credit, 0.0);
    });

    test('pendingDebt ignores stored credit and only tracks assigned minus collected', () {
      final retailer = Retailer(
        name: 'Shop',
        phone: '123',
        totalAssigned: 1000,
        totalCollected: 700,
        credit: 400,
      );

      expect(retailer.pendingDebt, 300.0);
    });
  });
}