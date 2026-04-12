import 'package:uuid/uuid.dart';

class Investor {
  final String id;
  final String name;
  final String phone;
  final double investedAmount;
  final double halfInvestedAmount;
  final double initialBusinessCapital;
  final double cumulativeCapitalBefore;
  final double halfCumulativeCapital;
  final double profitSharePercent;
  final String investmentDate;
  final int periodDays;
  final String status;
  final double totalProfitPaid;
  final String? notes;
  final String createdByUid;
  final int createdAt;

  Investor({
    String? id,
    required this.name,
    required this.phone,
    required this.investedAmount,
    required this.halfInvestedAmount,
    required this.initialBusinessCapital,
    required this.cumulativeCapitalBefore,
    required this.halfCumulativeCapital,
    required this.profitSharePercent,
    required this.investmentDate,
    this.periodDays = 30,
    this.status = 'active',
    this.totalProfitPaid = 0.0,
    this.notes,
    required this.createdByUid,
    int? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'investedAmount': investedAmount,
      'halfInvestedAmount': halfInvestedAmount,
      'initialBusinessCapital': initialBusinessCapital,
      'cumulativeCapitalBefore': cumulativeCapitalBefore,
      'halfCumulativeCapital': halfCumulativeCapital,
      'profitSharePercent': profitSharePercent,
      'investmentDate': investmentDate,
      'periodDays': periodDays,
      'status': status,
      'totalProfitPaid': totalProfitPaid,
      'notes': notes,
      'createdByUid': createdByUid,
      'createdAt': createdAt,
    };
  }

  factory Investor.fromMap(Map<String, dynamic> map) {
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

    return Investor(
      id: map['id'],
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      investedAmount: asDouble(map['investedAmount']),
      halfInvestedAmount: asDouble(map['halfInvestedAmount']),
      initialBusinessCapital: asDouble(map['initialBusinessCapital']),
      cumulativeCapitalBefore: asDouble(map['cumulativeCapitalBefore']),
      halfCumulativeCapital: asDouble(map['halfCumulativeCapital']),
      profitSharePercent: asDouble(map['profitSharePercent']),
      investmentDate: map['investmentDate'] ?? '',
      periodDays: asInt(map['periodDays']),
      status: map['status'] ?? 'active',
      totalProfitPaid: asDouble(map['totalProfitPaid']),
      notes: map['notes'],
      createdByUid: map['createdByUid'] ?? 'system',
      createdAt: asInt(map['createdAt']),
    );
  }
}
