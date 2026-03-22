import 'package:flutter_test/flutter_test.dart';
import 'package:vodafone_cash_tracker/models/retailer.dart';

void main() {
  test('Retailer fromMap', () {
    final map = {'name': 'Test', 'phone': '123'};
    final r = Retailer.fromMap(map);
    expect(r.credit, 0.0);
  });
}
