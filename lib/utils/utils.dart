// Utility Functions

import 'package:intl/intl.dart';

class DateTimeUtils {
  /// Format date to readable string
  static String formatDate(DateTime date) {
    return DateFormat('MMM dd, yyyy').format(date);
  }

  /// Format date and time
  static String formatDateTime(DateTime date) {
    return DateFormat('MMM dd, yyyy HH:mm').format(date);
  }

  /// Format time only
  static String formatTime(DateTime date) {
    return DateFormat('HH:mm').format(date);
  }

  /// Get relative time (e.g., "2 hours ago")
  static String getRelativeTime(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return formatDate(date);
    }
  }

  /// Check if date is today
  static bool isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  /// Check if date is this month
  static bool isThisMonth(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month;
  }

  /// Get start of day
  static DateTime getStartOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// Get end of day
  static DateTime getEndOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59);
  }

  /// Get start of month
  static DateTime getStartOfMonth(DateTime date) {
    return DateTime(date.year, date.month, 1);
  }

  /// Get end of month
  static DateTime getEndOfMonth(DateTime date) {
    return DateTime(date.year, date.month + 1, 0, 23, 59, 59);
  }
}

class CurrencyUtils {
  /// Format currency
  static String formatCurrency(double amount, {String symbol = 'EGP'}) {
    return '$symbol${amount.toStringAsFixed(2)}';
  }

  /// Parse currency string to double
  static double parseCurrency(String value) {
    return double.tryParse(value.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0;
  }

  /// Format exact numbers with commas instead of compact suffix (per client request)
  static String formatCompactNumber(double number) {
    // Used to return compact suffixes (K, M, B), now returns exact amounts with commas
    final formatter = NumberFormat('#,##0.00', 'en_US');
    return formatter.format(number);
  }
}

class ValidationUtils {
  /// Validate phone number
  static bool isValidPhoneNumber(String phone) {
    final phoneRegex = RegExp(r'^\+?[1-9]\d{1,14}$');
    return phoneRegex.hasMatch(phone.replaceAll(RegExp(r'\s'), ''));
  }

  /// Validate email
  static bool isValidEmail(String email) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(email);
  }

  /// Validate amount
  static bool isValidAmount(String amount) {
    final amountDouble = double.tryParse(amount);
    return amountDouble != null && amountDouble > 0;
  }

  /// Validate API key format
  static bool isValidApiKey(String key) {
    return key.isNotEmpty && key.length >= 20;
  }
}

class StringUtils {
  /// Truncate string with ellipsis
  static String truncate(String text, int length) {
    if (text.length <= length) return text;
    return '${text.substring(0, length)}...';
  }

  /// Capitalize first letter
  static String capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  /// Convert camelCase to Title Case
  static String camelCaseToTitleCase(String text) {
    return text
        .replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match.group(1)}')
        .trim()
        .split(' ')
        .map((word) => capitalize(word))
        .join(' ');
  }

  /// Mask sensitive data
  static String maskSensitiveData(String data) {
    if (data.length <= 4) return '****';
    final visible = data.substring(data.length - 4);
    return '${'*' * (data.length - 4)}$visible';
  }
}

class NumberUtils {
  /// Get percentage
  static double getPercentage(double value, double total) {
    if (total == 0) return 0;
    return (value / total).clamp(0, 1);
  }

  /// Round to decimal places
  static double roundToDecimal(double value, int places) {
    final mod = 10.0 * places;
    return (value * mod).round() / mod;
  }

  /// Check if number is within range
  static bool isInRange(double value, double min, double max) {
    return value >= min && value <= max;
  }

  /// Get absolute difference
  static double getAbsoluteDifference(double a, double b) {
    return (a - b).abs();
  }
}

class ListUtils {
  /// Remove duplicates from list
  static List<T> removeDuplicates<T>(List<T> list) {
    return list.toSet().toList();
  }

  /// Group list by key
  static Map<K, List<V>> groupBy<K, V>(
    List<V> list,
    K Function(V) keyFunction,
  ) {
    final map = <K, List<V>>{};
    for (var item in list) {
      final key = keyFunction(item);
      map.putIfAbsent(key, () => []).add(item);
    }
    return map;
  }

  /// Sort list by property
  static void sortBy<T>(
    List<T> list,
    Comparable Function(T) keyFunction, {
    bool ascending = true,
  }) {
    list.sort((a, b) {
      final comparison = keyFunction(a).compareTo(keyFunction(b));
      return ascending ? comparison : -comparison;
    });
  }
}
