import 'package:uuid/uuid.dart';

/// A merchant / shop that receives Vodafone Cash from us
/// and owes us liquid EGP.
class Retailer {
  final String id;
  final String name;
  final String phone;
  final String area;

  /// Total VF Cash assigned to this retailer (EGP)
  final double totalAssigned;

  /// Cash already collected from this retailer (EGP)
  final double totalCollected;

  /// Pending debt = totalAssigned - totalCollected
  double get pendingDebt => totalAssigned - totalCollected;

  final bool isActive;
  final DateTime createdAt;
  final DateTime lastUpdatedAt;

  /// UID of the collector assigned to collect from this retailer.
  /// null means unassigned (no collector is responsible).
  final String? assignedCollectorId;

  /// Discount rate per 1000 EGP distributed to this retailer.
  /// Example: -1 means for every 1000 EGP VF Cash sent, their debt increases by 999 EGP.
  final double discountPer1000;

  Retailer({
    String? id,
    required this.name,
    required this.phone,
    this.area = '',
    this.totalAssigned = 0.0,
    this.totalCollected = 0.0,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? lastUpdatedAt,
    this.assignedCollectorId,
    this.discountPer1000 = 0.0,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        lastUpdatedAt = lastUpdatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'area': area,
        'totalAssigned': totalAssigned,
        'totalCollected': totalCollected,
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
        'lastUpdatedAt': lastUpdatedAt.toIso8601String(),
        'assignedCollectorId': assignedCollectorId,
        'discountPer1000': discountPer1000,
      };

  factory Retailer.fromMap(Map<String, dynamic> map) {
    double asDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString().replaceAll(',', '')) ?? 0.0;
    }

    return Retailer(
      id: map['id']?.toString() ?? const Uuid().v4(),
      name: map['name']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      area: map['area']?.toString() ?? '',
      totalAssigned: asDouble(map['totalAssigned']),
      totalCollected: asDouble(map['totalCollected']),
      isActive: (map['isActive'] is bool) ? map['isActive'] : true,
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.now(),
      lastUpdatedAt: DateTime.tryParse(map['lastUpdatedAt']?.toString() ?? '') ?? DateTime.now(),
      assignedCollectorId: map['assignedCollectorId']?.toString(),
      discountPer1000: asDouble(map['discountPer1000']),
    );
  }

  Retailer copyWith({
    String? name,
    String? phone,
    String? area,
    double? totalAssigned,
    double? totalCollected,
    bool? isActive,
    DateTime? lastUpdatedAt,
    double? discountPer1000,
    Object? assignedCollectorId = _sentinel,
  }) =>
      Retailer(
        id: id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        area: area ?? this.area,
        totalAssigned: totalAssigned ?? this.totalAssigned,
        totalCollected: totalCollected ?? this.totalCollected,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
        assignedCollectorId: assignedCollectorId == _sentinel
            ? this.assignedCollectorId
            : assignedCollectorId as String?,
        discountPer1000: discountPer1000 ?? this.discountPer1000,
      );
}

// Sentinel for nullable copyWith
const Object _sentinel = Object();
