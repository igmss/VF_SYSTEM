import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:uuid/uuid.dart';

import '../models/retailer_assignment_request.dart';

class RetailerPortalService {
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-east1');
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  /// Business data + filtered ledger activity (see Cloud Function).
  Future<Map<String, dynamic>> getPortalData({int? startMs, int? endMs}) async {
    final result = await _functions.httpsCallable('getRetailerPortalData').call({
      if (startMs != null) 'startMs': startMs,
      if (endMs != null) 'endMs': endMs,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  Stream<List<RetailerAssignmentRequest>> streamRequestsForUser(String retailerUserUid) {
    return _db.ref('retailer_portal/$retailerUserUid/requests').onValue.map((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null || snap.value is! Map) {
        return <RetailerAssignmentRequest>[];
      }
      final map = Map<String, dynamic>.from(snap.value as Map);
      final list = <RetailerAssignmentRequest>[];
      map.forEach((key, value) {
        if (value is Map) {
          list.add(RetailerAssignmentRequest.fromMap(
            key.toString(),
            Map<String, dynamic>.from(value),
          ));
        }
      });
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Admin: all requests across retailer portal accounts.
  Stream<List<RetailerPortalRequestRow>> streamAllRequests() {
    return _db.ref('retailer_portal').onValue.map((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null || snap.value is! Map) {
        return <RetailerPortalRequestRow>[];
      }
      final root = snap.value as Map;
      final list = <RetailerPortalRequestRow>[];
      root.forEach((userUid, userVal) {
        if (userVal is! Map) return;
        final reqMap = userVal['requests'];
        if (reqMap is! Map) return;
        reqMap.forEach((rid, rdata) {
          if (rdata is Map) {
            list.add(RetailerPortalRequestRow(
              portalUserUid: userUid.toString(),
              request: RetailerAssignmentRequest.fromMap(
                rid.toString(),
                Map<String, dynamic>.from(rdata),
              ),
            ));
          }
        });
      });
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
    final id = const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.ref('retailer_portal/$retailerUserUid/requests/$id').set({
      'id': id,
      'retailerId': retailerId,
      'createdByUid': createdByUid,
      'requestedAmount': requestedAmount,
      'vfPhoneNumber': vfPhoneNumber.trim(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      'status': 'PENDING',
      'createdAt': now,
      'updatedAt': now,
    });
  }

  Future<void> updateRequestAdmin({
    required String portalUserUid,
    required String requestId,
    required Map<String, dynamic> updates,
  }) async {
    final u = Map<String, dynamic>.from(updates);
    u['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    await _db.ref('retailer_portal/$portalUserUid/requests/$requestId').update(u);
  }

  Future<void> lockRequestAdmin({
    required String portalUserUid,
    required String requestId,
    required String adminUid,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.ref('retailer_portal/$portalUserUid/requests/$requestId').update({
      'status': 'PROCESSING',
      'processingBy': adminUid,
      'updatedAt': now,
    });
  }

  Future<void> unlockRequestAdmin({
    required String portalUserUid,
    required String requestId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.ref('retailer_portal/$portalUserUid/requests/$requestId').update({
      'status': 'PENDING',
      'processingBy': null,
      'updatedAt': now,
    });
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
