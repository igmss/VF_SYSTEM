import 'package:uuid/uuid.dart';

enum ExpenseSource {
  BANK,
  VF_CASH,
  COLLECTOR_CASH,
}

extension ExpenseSourceExtension on ExpenseSource {
  String get label {
    switch (this) {
      case ExpenseSource.BANK: return 'Bank';
      case ExpenseSource.VF_CASH: return 'VF Cash';
      case ExpenseSource.COLLECTOR_CASH: return 'Collector Cash';
    }
  }

  static ExpenseSource fromString(String s) {
    return ExpenseSource.values.firstWhere(
      (e) => e.toString().split('.').last == s || e.label == s,
      orElse: () => ExpenseSource.BANK,
    );
  }
}

class Expense {
  final String id;
  final double amount;
  final String category;
  final ExpenseSource source;
  final String sourceId;
  final String sourceLabel;
  final String? notes;
  final DateTime timestamp;
  final String createdByUid;

  Expense({
    String? id,
    required this.amount,
    required this.category,
    required this.source,
    required this.sourceId,
    required this.sourceLabel,
    this.notes,
    DateTime? timestamp,
    required this.createdByUid,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'amount': amount,
        'category': category,
        'source': source.toString().split('.').last,
        'sourceId': sourceId,
        'sourceLabel': sourceLabel,
        if (notes != null) 'notes': notes,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'createdByUid': createdByUid,
      };

  factory Expense.fromMap(Map<String, dynamic> map) {
    double asDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    final ts = map['timestamp'];
    DateTime time;
    if (ts is int) {
      time = DateTime.fromMillisecondsSinceEpoch(ts);
    } else {
      time = DateTime.tryParse(ts?.toString() ?? '') ?? DateTime.now();
    }

    return Expense(
      id: map['id']?.toString() ?? const Uuid().v4(),
      amount: asDouble(map['amount']),
      category: map['category']?.toString() ?? 'General',
      source: ExpenseSourceExtension.fromString(map['source']?.toString() ?? 'BANK'),
      sourceId: map['sourceId']?.toString() ?? '',
      sourceLabel: map['sourceLabel']?.toString() ?? '',
      notes: map['notes']?.toString(),
      timestamp: time,
      createdByUid: map['createdByUid']?.toString() ?? 'system',
    );
  }
}
