import 'package:flutter_test/flutter_test.dart';
import 'package:vodafone_cash_tracker/models/models.dart';

void main() {
  group('CashTransaction.fromMap', () {
    test('parses numeric strings and timestamps defensively', () {
      final transaction = CashTransaction.fromMap({
        'id': 42,
        'phoneNumber': 20123,
        'amount': '1,250.50',
        'currency': 99,
        'timestamp': '1711459200000',
        'bybitOrderId': 12345,
        'status': 'done',
        'paymentMethod': 7,
        'side': '0',
        'chatHistory': 123,
        'price': '49.75',
        'quantity': '25.135',
        'token': 55,
      });

      expect(transaction.id, '42');
      expect(transaction.phoneNumber, '20123');
      expect(transaction.amount, 1250.50);
      expect(transaction.currency, '99');
      expect(transaction.timestamp.millisecondsSinceEpoch, 1711459200000);
      expect(transaction.bybitOrderId, '12345');
      expect(transaction.paymentMethod, '7');
      expect(transaction.side, 0);
      expect(transaction.chatHistory, '123');
      expect(transaction.price, 49.75);
      expect(transaction.quantity, 25.135);
      expect(transaction.token, '55');
    });
  });
}
