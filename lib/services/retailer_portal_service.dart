import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/retailer_assignment_request.dart';
import '../models/financial_transaction.dart';
import '../models/retailer.dart';

class RetailerPortalService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Business data + filtered ledger activity.
  Future<Map<String, dynamic>> getPortalData({int? startMs, int? endMs}) async {
    final response = await _supabase.functions.invoke('get-retailer-portal-data', body: {
      if (startMs != null) 'startMs': startMs.toString(),
      if (endMs != null) 'endMs': endMs.toString(),
    });

    if (response.status != 200) {
      throw Exception(response.data['error'] ?? 'Failed to fetch portal data');
    }

    final data = response.data as Map<String, dynamic>;
    final retailerMap = data['retailer'] as Map<String, dynamic>;
    final activityList = data['activity'] as List;

    return {
      'retailer': Retailer.fromMap(retailerMap).toMap(),
      'retailerId': data['retailerId'],
      'activity': activityList.map((r) => FinancialTransaction.fromMap(r as Map<String, dynamic>, r['id'].toString()).toMap()).toList(),
      'range': data['range'],
    };
  }

  Stream<List<RetailerAssignmentRequest>> streamRequestsForUser(String retailerUserUid) {
    // Note: We filter by created_by_uid = retailerUserUid
    return _supabase
        .from('retailer_assignment_requests')
        .stream(primaryKey: ['id'])
        .eq('created_by_uid', retailerUserUid)
        .map((rows) {
          final list = rows.map((r) => RetailerAssignmentRequest.fromMap(r['id'].toString(), r)).toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  /// Admin: all requests across retailer portal accounts.
  Stream<List<RetailerPortalRequestRow>> streamAllRequests() {
    return _supabase
        .from('retailer_assignment_requests')
        .stream(primaryKey: ['id'])
        .map((rows) {
          final list = rows.map((r) {
            final request = RetailerAssignmentRequest.fromMap(r['id'].toString(), r);
            return RetailerPortalRequestRow(
              portalUserUid: request.createdByUid,
              request: request,
            );
          }).toList();
          list.sort((a, b) => b.request.createdAt.compareTo(a.request.createdAt));
          return list;
        });
  }

  Future<void> createRequest({
    required String retailerUserUid,
    required String retailerId,
    required String createdByUid,
    required double requestedAmount,
    required String vfPhoneNumber,
    String? notes,
  }) async {
    await _supabase.from('retailer_assignment_requests').insert({
      'retailer_id': retailerId,
      'created_by_uid': createdByUid,
      'requested_amount': requestedAmount,
      'vf_phone_number': vfPhoneNumber.trim(),
      'notes': notes?.trim(),
      'status': 'PENDING',
    });
  }

  Future<void> updateRequestAdmin({
    required String portalUserUid,
    required String requestId,
    required Map<String, dynamic> updates,
  }) async {
    // Map camelCase to snake_case for updates
    final mappedUpdates = <String, dynamic>{};
    if (updates.containsKey('status')) mappedUpdates['status'] = updates['status'];
    if (updates.containsKey('assignedAmount')) mappedUpdates['assigned_amount'] = updates['assignedAmount'];
    if (updates.containsKey('adminNotes')) mappedUpdates['admin_notes'] = updates['adminNotes'];
    if (updates.containsKey('rejectedReason')) mappedUpdates['rejected_reason'] = updates['rejectedReason'];
    if (updates.containsKey('proofImageUrl')) mappedUpdates['proof_image_url'] = updates['proofImageUrl'];
    
    mappedUpdates['updated_at'] = DateTime.now().toIso8601String();

    await _supabase
        .from('retailer_assignment_requests')
        .update(mappedUpdates)
        .eq('id', requestId);
  }

  Future<void> lockRequestAdmin({
    required String portalUserUid,
    required String requestId,
    required String adminUid,
  }) async {
    final bool success = await _supabase.rpc('lock_retailer_request', params: {
      'p_request_id': requestId,
      'p_admin_uid': adminUid,
    });

    if (!success) {
      throw Exception('Request is no longer PENDING and could not be locked.');
    }
  }

  Future<void> unlockRequestAdmin({
    required String portalUserUid,
    required String requestId,
  }) async {
    await _supabase
        .from('retailer_assignment_requests')
        .update({
          'status': 'PENDING',
          'processing_by': null,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', requestId);
  }
}

class RetailerPortalRequestRow {
  final String portalUserUid;
  final RetailerAssignmentRequest request;

  RetailerPortalRequestRow({
    required this.portalUserUid,
    required this.request,
  });
}
