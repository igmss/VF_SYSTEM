import 'package:uuid/uuid.dart';

/// A team member (runner) who collects liquid cash from retailers
/// and deposits it back into bank accounts.
class Collector {
  final String id;
  final String name;
  final String phone;
  final String? email;

  /// Firebase Auth UID — links this record to the collector's login account.
  final String? uid;

  /// Cash currently held by this collector (not yet deposited)
  final double cashOnHand;

  /// Maximum cash this collector can hold
  final double cashLimit;

  /// Total cash collected over all time
  final double totalCollected;

  /// Total cash deposited over all time
  final double totalDeposited;

  final bool isActive;
  final DateTime createdAt;
  final DateTime lastUpdatedAt;

  Collector({
    String? id,
    required this.name,
    required this.phone,
    this.email,
    this.uid,
    this.cashOnHand = 0.0,
    this.cashLimit = 50000.0,
    this.totalCollected = 0.0,
    this.totalDeposited = 0.0,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? lastUpdatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        lastUpdatedAt = lastUpdatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'email': email,
        'uid': uid,
        'cashOnHand': cashOnHand,
        'cashLimit': cashLimit,
        'totalCollected': totalCollected,
        'totalDeposited': totalDeposited,
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
        'lastUpdatedAt': lastUpdatedAt.toIso8601String(),
      };

  factory Collector.fromMap(Map<String, dynamic> map) {
    double asDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    return Collector(
      id: map['id']?.toString() ?? const Uuid().v4(),
      name: map['name']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      email: map['email']?.toString(),
      uid: map['uid']?.toString(),
      cashOnHand: asDouble(map['cash_on_hand'] ?? map['cashOnHand']),
      cashLimit: asDouble(map['cash_limit'] ?? map['cashLimit'] ?? 50000.0),
      totalCollected: asDouble(map['total_collected'] ?? map['totalCollected']),
      totalDeposited: asDouble(map['total_deposited'] ?? map['totalDeposited']),
      isActive: (map['is_active'] ?? map['isActive']) == true,
      createdAt: DateTime.tryParse((map['created_at'] ?? map['createdAt'])?.toString() ?? '') ?? DateTime.now(),
      lastUpdatedAt: DateTime.tryParse((map['last_updated_at'] ?? map['lastUpdatedAt'])?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Collector copyWith({
    String? name,
    String? phone,
    String? email,
    String? uid,
    double? cashOnHand,
    double? cashLimit,
    double? totalCollected,
    double? totalDeposited,
    bool? isActive,
    DateTime? lastUpdatedAt,
  }) =>
      Collector(
        id: id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        uid: uid ?? this.uid,
        cashOnHand: cashOnHand ?? this.cashOnHand,
        cashLimit: cashLimit ?? this.cashLimit,
        totalCollected: totalCollected ?? this.totalCollected,
        totalDeposited: totalDeposited ?? this.totalDeposited,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      );
}
