import 'package:uuid/uuid.dart';

class Investor {
  final String id;
  final String name;
  final double investmentAmount;
  final int priority;
  final double profitSharePercentage;
  final String createdByUid;
  final DateTime createdAt;

  Investor({
    String? id,
    required this.name,
    required this.investmentAmount,
    this.priority = 1,
    this.profitSharePercentage = 100.0,
    required this.createdByUid,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'investmentAmount': investmentAmount,
        'priority': priority,
        'profitSharePercentage': profitSharePercentage,
        'createdByUid': createdByUid,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory Investor.fromMap(Map<String, dynamic> map) {
    double asDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    int asInt(dynamic v) {
      if (v == null) return 1;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 1;
    }

    final ts = map['createdAt'];
    DateTime time;
    if (ts is int) {
      time = DateTime.fromMillisecondsSinceEpoch(ts);
    } else {
      time = DateTime.tryParse(ts?.toString() ?? '') ?? DateTime.now();
    }

    return Investor(
      id: map['id']?.toString() ?? const Uuid().v4(),
      name: map['name']?.toString() ?? 'Unknown Investor',
      investmentAmount: asDouble(map['investmentAmount']),
      priority: asInt(map['priority']),
      profitSharePercentage: map['profitSharePercentage'] != null ? asDouble(map['profitSharePercentage']) : 100.0,
      createdByUid: map['createdByUid']?.toString() ?? 'system',
      createdAt: time,
    );
  }
}
