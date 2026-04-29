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

    DateTime asDT(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      return DateTime.tryParse(v.toString()) ?? DateTime.now();
    }

    final createdAtDt = asDT(map['created_at'] ?? map['createdAt']);
    final updatedAtDt = asDT(map['updated_at'] ?? map['updatedAt']);
    final completedAtDt = (map['completed_at'] ?? map['completedAt']) != null 
        ? asDT(map['completed_at'] ?? map['completedAt']) 
        : null;

    return RetailerAssignmentRequest(
      id: map['id']?.toString() ?? id,
      retailerId: (map['retailer_id'] ?? map['retailerId'])?.toString() ?? '',
      createdByUid: (map['created_by_uid'] ?? map['createdByUid'])?.toString() ?? '',
      requestedAmount: asD(map['requested_amount'] ?? map['requestedAmount']),
      vfPhoneNumber: (map['vf_phone_number'] ?? map['vfPhoneNumber'])?.toString() ?? '',
      notes: map['notes']?.toString(),
      status: map['status']?.toString() ?? 'PENDING',
      createdAt: createdAtDt.millisecondsSinceEpoch,
      updatedAt: updatedAtDt.millisecondsSinceEpoch,
      assignedAmount: (map['assigned_amount'] ?? map['assignedAmount']) != null 
          ? asD(map['assigned_amount'] ?? map['assignedAmount']) 
          : null,
      adminNotes: (map['admin_notes'] ?? map['adminNotes'])?.toString(),
      proofImageUrl: (map['proof_image_url'] ?? map['proofImageUrl'])?.toString(),
      completedAt: completedAtDt?.millisecondsSinceEpoch,
      completedByUid: (map['completed_by_uid'] ?? map['completedByUid'])?.toString(),
      rejectedReason: (map['rejected_reason'] ?? map['rejectedReason'])?.toString(),
      processingBy: (map['processing_by'] ?? map['processingBy'])?.toString(),
    );
  }
}
