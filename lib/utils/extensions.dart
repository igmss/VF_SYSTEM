// Extension methods for common operations

extension StringExtension on String {
  /// Capitalize first letter
  String get capitalized {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }

  /// Reverse string
  String get reversed => split('').reversed.join('');

  /// Check if string is numeric
  bool get isNumeric => double.tryParse(this) != null;

  /// Remove all whitespace
  String get removeWhitespace => replaceAll(RegExp(r'\s+'), '');

  /// Truncate string with ellipsis
  String truncate(int length) {
    if (this.length <= length) return this;
    return '${substring(0, length)}...';
  }
}

extension DoubleExtension on double {
  /// Format as currency
  String toCurrency({String symbol = 'EGP'}) {
    return '$symbol${toStringAsFixed(2)}';
  }

  /// Format as percentage
  String toPercentage({int decimals = 1}) {
    return '${(this * 100).toStringAsFixed(decimals)}%';
  }

  /// Check if value is between range
  bool isBetween(double min, double max) {
    return this >= min && this <= max;
  }

  /// Clamp value between min and max
  double clampBetween(double min, double max) {
    if (this < min) return min;
    if (this > max) return max;
    return this;
  }

  /// Round to decimal places
  double roundToDecimal(int places) {
    final mod = 10.0 * places;
    return (this * mod).round() / mod;
  }
}

extension IntExtension on int {
  /// Format as currency
  String toCurrency({String symbol = 'EGP'}) {
    return '$symbol${toDouble().toStringAsFixed(2)}';
  }

  /// Check if value is between range
  bool isBetween(int min, int max) {
    return this >= min && this <= max;
  }

  /// Convert to duration
  Duration get milliseconds => Duration(milliseconds: this);
  Duration get seconds => Duration(seconds: this);
  Duration get minutes => Duration(minutes: this);
  Duration get hours => Duration(hours: this);
  Duration get days => Duration(days: this);
}

extension DateTimeExtension on DateTime {
  /// Format date
  String get formatted => toString().split('.')[0];

  /// Check if date is today
  bool get isToday {
    final now = DateTime.now();
    return year == now.year && month == now.month && day == now.day;
  }

  /// Check if date is yesterday
  bool get isYesterday {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return year == yesterday.year &&
        month == yesterday.month &&
        day == yesterday.day;
  }

  /// Check if date is this month
  bool get isThisMonth {
    final now = DateTime.now();
    return year == now.year && month == now.month;
  }

  /// Check if date is this year
  bool get isThisYear {
    return year == DateTime.now().year;
  }

  /// Get start of day
  DateTime get startOfDay => DateTime(year, month, day);

  /// Get end of day
  DateTime get endOfDay => DateTime(year, month, day, 23, 59, 59);

  /// Get start of month
  DateTime get startOfMonth => DateTime(year, month, 1);

  /// Get end of month
  DateTime get endOfMonth => DateTime(year, month + 1, 0, 23, 59, 59);

  /// Add days
  DateTime addDays(int days) => add(Duration(days: days));

  /// Subtract days
  DateTime subtractDays(int days) => subtract(Duration(days: days));

  /// Add months
  DateTime addMonths(int months) {
    var month = this.month + months;
    var year = this.year;
    while (month > 12) {
      month -= 12;
      year += 1;
    }
    while (month < 1) {
      month += 12;
      year -= 1;
    }
    return DateTime(year, month, day);
  }
}

extension ListExtension<T> on List<T> {
  /// Get first element or null
  T? get firstOrNull => isEmpty ? null : first;

  /// Get last element or null
  T? get lastOrNull => isEmpty ? null : last;

  /// Get random element
  T? getRandomElement() {
    if (isEmpty) return null;
    return this[(DateTime.now().millisecond) % length];
  }

  /// Remove duplicates
  List<T> removeDuplicates() {
    return toSet().toList();
  }

  /// Reverse list into a new list
  List<T> get reversedList => List<T>.from(this.reversed);

  /// Chunk list into smaller lists
  List<List<T>> chunk(int size) {
    final chunks = <List<T>>[];
    for (var i = 0; i < length; i += size) {
      chunks.add(sublist(i, i + size > length ? length : i + size));
    }
    return chunks;
  }
}

extension MapExtension<K, V> on Map<K, V> {
  /// Get value or default
  V? getOrDefault(K key, V? defaultValue) {
    return containsKey(key) ? this[key] : defaultValue;
  }

  /// Get all keys as list
  List<K> get keysList => keys.toList();

  /// Get all values as list
  List<V> get valuesList => values.toList();

  /// Merge with another map
  Map<K, V> merge(Map<K, V> other) {
    return {...this, ...other};
  }
}
