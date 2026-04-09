import 'package:uuid/uuid.dart';

enum LoanSourceType {
  bank,
  collector,
}

enum LoanStatus {
  active,
  fully_repaid,
}

class Loan {
  final String id;
  final String borrowerName;
  final String borrowerPhone;
  final double principalAmount;
  final double amountRepaid;
  final LoanSourceType sourceType;
  final String sourceId;
  final String sourceLabel;
  final LoanStatus status;
  final DateTime issuedAt;
  final DateTime lastUpdatedAt;
  final String? notes;
  final String createdByUid;

  Loan({
    String? id,
    required this.borrowerName,
    required this.borrowerPhone,
    required this.principalAmount,
    this.amountRepaid = 0.0,
    required this.sourceType,
    required this.sourceId,
    required this.sourceLabel,
    this.status = LoanStatus.active,
    DateTime? issuedAt,
    DateTime? lastUpdatedAt,
    this.notes,
    required this.createdByUid,
  })  : id = id ?? const Uuid().v4(),
        issuedAt = issuedAt ?? DateTime.now(),
        lastUpdatedAt = lastUpdatedAt ?? DateTime.now();

  double get outstandingBalance => principalAmount - amountRepaid;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'borrowerName': borrowerName,
      'borrowerPhone': borrowerPhone,
      'principalAmount': principalAmount,
      'amountRepaid': amountRepaid,
      'sourceType': sourceType.name,
      'sourceId': sourceId,
      'sourceLabel': sourceLabel,
      'status': status.name,
      'issuedAt': issuedAt.millisecondsSinceEpoch,
      'lastUpdatedAt': lastUpdatedAt.millisecondsSinceEpoch,
      'notes': notes,
      'createdByUid': createdByUid,
    };
  }

  factory Loan.fromMap(Map<String, dynamic> map) {
    double asDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    DateTime asDateTime(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      return DateTime.tryParse(v.toString()) ?? DateTime.now();
    }

    return Loan(
      id: map['id'],
      borrowerName: map['borrowerName'] ?? '',
      borrowerPhone: map['borrowerPhone'] ?? '',
      principalAmount: asDouble(map['principalAmount']),
      amountRepaid: asDouble(map['amountRepaid']),
      sourceType: LoanSourceType.values.firstWhere(
        (e) => e.name == map['sourceType'],
        orElse: () => LoanSourceType.bank,
      ),
      sourceId: map['sourceId'] ?? '',
      sourceLabel: map['sourceLabel'] ?? '',
      status: LoanStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => LoanStatus.active,
      ),
      issuedAt: asDateTime(map['issuedAt']),
      lastUpdatedAt: asDateTime(map['lastUpdatedAt']),
      notes: map['notes'],
      createdByUid: map['createdByUid'] ?? 'system',
    );
  }
}
