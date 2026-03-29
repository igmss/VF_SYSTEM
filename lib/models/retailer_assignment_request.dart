/// Assignment / VF amount request stored under
/// `retailer_portal/{retailerUserUid}/requests/{requestId}`.
class RetailerAssignmentRequest {
  final String id;
  final String retailerId;
  final String createdByUid;
  final double requestedAmount;
  final String vfPhoneNumber;
  final String? notes;
  final String status;

  /// ms since epoch
  final int createdAt;
  final int updatedAt;

  final double? assignedAmount;
  final String? adminNotes;
  final String? proofImageUrl;
  final String? rejectedReason;
  final String? processingBy;
  final int? completedAt;
  final String? completedByUid;

  RetailerAssignmentRequest({
    required this.id,
    required this.retailerId,
    required this.createdByUid,
    required this.requestedAmount,
    required this.vfPhoneNumber,
    this.notes,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.assignedAmount,
    this.adminNotes,
    this.proofImageUrl,
    this.rejectedReason,
    this.processingBy,
    this.completedAt,
    this.completedByUid,
  });

  factory RetailerAssignmentRequest.fromMap(String id, Map<String, dynamic> map) {
    double asD(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0;
    }

    int? asI(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return RetailerAssignmentRequest(
      id: map['id']?.toString() ?? id,
      retailerId: map['retailerId']?.toString() ?? '',
      createdByUid: map['createdByUid']?.toString() ?? '',
      requestedAmount: asD(map['requestedAmount']),
      vfPhoneNumber: map['vfPhoneNumber']?.toString() ?? '',
      notes: map['notes']?.toString(),
      status: map['status']?.toString() ?? 'PENDING',
      createdAt: asI(map['createdAt']) ?? 0,
      updatedAt: asI(map['updatedAt']) ?? 0,
      assignedAmount: map['assignedAmount'] != null ? asD(map['assignedAmount']) : null,
      adminNotes: map['adminNotes']?.toString(),
      proofImageUrl: map['proofImageUrl']?.toString(),
      completedAt: asI(map['completedAt']),
      completedByUid: map['completedByUid']?.toString(),
      rejectedReason: map['rejectedReason']?.toString(),
      processingBy: map['processingBy']?.toString(),
    );
  }
}
