import 'package:intl/intl.dart';

class Formatters {
  static String formatCurrency(num amount) {
    return NumberFormat.currency(symbol: 'EGP ', decimalDigits: 2).format(amount);
  }

  static String formatNumber(num number) {
    return NumberFormat('#,##0.00', 'en_US').format(number);
  }
}
