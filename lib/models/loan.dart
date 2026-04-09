import 'package:uuid/uuid.dart';

enum LoanStatus {
  ACTIVE,
  COMPLETED,
  DEFAULTED
}

extension LoanStatusExtension on LoanStatus {
  String get label {
    switch (this) {
      case LoanStatus.ACTIVE: return 'Active';
      case LoanStatus.COMPLETED: return 'Completed';
      case LoanStatus.DEFAULTED: return 'Defaulted';
    }
  }

  static LoanStatus fromString(String s) {
    return LoanStatus.values.firstWhere(
      (e) => e.toString().split('.').last == s || e.label == s,
      orElse: () => LoanStatus.ACTIVE,
    );
  }
}

class Loan {
  final String id;
  final String borrowerName;
  final double principal;
  final double repaidAmount;
  final LoanStatus status;
  final String? notes;
  final DateTime issuedAt;
  final String createdByUid;

  Loan({
    String? id,
    required this.borrowerName,
    required this.principal,
    this.repaidAmount = 0.0,
    this.status = LoanStatus.ACTIVE,
    this.notes,
    DateTime? issuedAt,
    required this.createdByUid,
  })  : id = id ?? const Uuid().v4(),
        issuedAt = issuedAt ?? DateTime.now();

  double get remainingAmount => principal - repaidAmount;

  bool get isPaidOff => remainingAmount <= 0;

  Map<String, dynamic> toMap() => {
        'id': id,
        'borrowerName': borrowerName,
        'principal': principal,
        'repaidAmount': repaidAmount,
        'status': status.toString().split('.').last,
        if (notes != null) 'notes': notes,
        'issuedAt': issuedAt.millisecondsSinceEpoch,
        'createdByUid': createdByUid,
      };

  factory Loan.fromMap(Map<String, dynamic> map) {
    double asDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    final ts = map['issuedAt'];
    DateTime time;
    if (ts is int) {
      time = DateTime.fromMillisecondsSinceEpoch(ts);
    } else {
      time = DateTime.tryParse(ts?.toString() ?? '') ?? DateTime.now();
    }

    return Loan(
      id: map['id']?.toString() ?? const Uuid().v4(),
      borrowerName: map['borrowerName']?.toString() ?? 'Unknown Borrower',
      principal: asDouble(map['principal']),
      repaidAmount: asDouble(map['repaidAmount']),
      status: LoanStatusExtension.fromString(map['status']?.toString() ?? 'ACTIVE'),
      notes: map['notes']?.toString(),
      issuedAt: time,
      createdByUid: map['createdByUid']?.toString() ?? 'system',
    );
  }
}
