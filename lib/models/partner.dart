import 'package:uuid/uuid.dart';

class Partner {
  final String id;
  final String name;
  final double sharePercent;
  final double totalProfitPaid;
  final int createdAt;
  final String status;

  Partner({
    String? id,
    required this.name,
    required this.sharePercent,
    this.totalProfitPaid = 0.0,
    int? createdAt,
    this.status = 'active',
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'sharePercent': sharePercent,
      'totalProfitPaid': totalProfitPaid,
      'createdAt': createdAt,
      'status': status,
    };
  }

  factory Partner.fromMap(Map<String, dynamic> map) {
    double asDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    int asInt(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    return Partner(
      id: map['id'],
      name: map['name'] ?? '',
      sharePercent: asDouble(map['sharePercent']),
      totalProfitPaid: asDouble(map['totalProfitPaid']),
      createdAt: asInt(map['createdAt']),
      status: map['status'] ?? 'active',
    );
  }
}
