import 'dart:async';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../providers/distribution_provider.dart';
import 'retailer_portal_service.dart';
import 'ussd_service.dart';

/// Outcome of a full lock → USSD → screenshot → finalize flow.
class RetailerUssdRunResult {
  final bool success;
  final String message;
  /// True if [unlockRequestAdmin] ran (request returned to PENDING). False if still PROCESSING or completed.
  final bool didUnlock;

  const RetailerUssdRunResult({
    required this.success,
    required this.message,
    this.didUnlock = false,
  });
}

/// Shared, sequential-safe USSD assignment pipeline (manual sheet + auto queue).
class RetailerAssignmentUssdRunner {
  RetailerAssignmentUssdRunner._();

  static const int _maxRetries = 2;

  static double _estimateFeesForBalance({
    required double amount,
    required bool isExternalWallet,
  }) {
    if (!isExternalWallet) return 0;
    var calcFee = amount * 0.005;
    if (calcFee > 15.0) calcFee = 15.0;
    return calcFee;
  }

  /// Minimum balance check before locking (conservative: transfer + external est. + max 15 VF fee).
  static bool hasLikelySufficientBalance({
    required MobileNumber vfNumber,
    required double amount,
    required bool isExternalWallet,
  }) {
    final est = _estimateFeesForBalance(amount: amount, isExternalWallet: isExternalWallet);
    const maxVodafoneFee = 15.0;
    final required = amount + est + maxVodafoneFee;
    return vfNumber.currentBalance >= required;
  }

  /// Runs USSD after [lockRequestAdmin] — owns lock/unlock for failures and timeouts.
  static Future<RetailerUssdRunResult> run({
    required RetailerPortalRequestRow row,
    required String adminUid,
    required String selectedNumId,
    required double amount,
    required double formFees,
    required bool isExternalWallet,
    required bool applyCredit,
    required String adminNotes,
    required DistributionProvider distribution,
    required AppProvider app,
    required RetailerPortalService portal,
    void Function()? onSuccessUi,
  }) async {
    if (amount <= 0) {
      return const RetailerUssdRunResult(success: false, message: 'Invalid amount', didUnlock: false);
    }

    try {
      app.mobileNumbers.firstWhere((n) => n.id == selectedNumId);
    } catch (_) {
      return const RetailerUssdRunResult(success: false, message: 'VF number not found', didUnlock: false);
    }

    try {
      await portal.lockRequestAdmin(
        portalUserUid: row.portalUserUid,
        requestId: row.request.id,
        adminUid: adminUid,
      );
    } catch (e) {
      return RetailerUssdRunResult(success: false, message: 'Could not lock request: $e', didUnlock: false);
    }

    return _runTransferLoop(
      row: row,
      adminUid: adminUid,
      selectedNumId: selectedNumId,
      amount: amount,
      formFees: formFees,
      isExternalWallet: isExternalWallet,
      applyCredit: applyCredit,
      adminNotes: adminNotes,
      distribution: distribution,
      app: app,
      portal: portal,
      onSuccessUi: onSuccessUi,
      retryCount: 0,
    );
  }

  static Future<RetailerUssdRunResult> _runTransferLoop({
    required RetailerPortalRequestRow row,
    required String adminUid,
    required String selectedNumId,
    required double amount,
    required double formFees,
    required bool isExternalWallet,
    required bool applyCredit,
    required String adminNotes,
    required DistributionProvider distribution,
    required AppProvider app,
    required RetailerPortalService portal,
    required int retryCount,
    void Function()? onSuccessUi,
  }) async {
    final srcNum = app.mobileNumbers.firstWhere((n) => n.id == selectedNumId);

    final expectedSessionId = const Uuid().v4();
    StreamSubscription<UssdResponse>? sub;
    Timer? timeoutTimer;
    double? bufferedFee;
    final completer = Completer<RetailerUssdRunResult>();
    var finished = false;

    Future<void> safeComplete(RetailerUssdRunResult r) async {
      if (finished) return;
      finished = true;
      timeoutTimer?.cancel();
      await sub?.cancel();
      if (!completer.isCompleted) completer.complete(r);
    }

    Future<void> handleFailure(String errorMsg) async {
      if (finished) return;

      // Without balance check, any failure or timeout is risky.
      // Move to MANUAL_REVIEW to prevent double-transfer.
      try {
        await portal.updateRequestAdmin(
          portalUserUid: row.portalUserUid,
          requestId: row.request.id,
          updates: {
            'status': 'MANUAL_REVIEW',
            'adminNotes': 'USSD failed/timed out ($errorMsg). Moved to MANUAL_REVIEW for safety (balance check disabled).',
          },
        );
      } catch (_) {}
      await safeComplete(RetailerUssdRunResult(success: false, message: errorMsg, didUnlock: false));
    }

    timeoutTimer = Timer(const Duration(minutes: 5), () => handleFailure('USSD timed out'));

    sub = UssdService.onUpdate.listen((resp) async {
      if (finished || resp.sessionId != expectedSessionId) return;

      if (resp.extractedFee != null) bufferedFee = resp.extractedFee;

      if (resp.status == UssdStatus.success && resp.screenshotPath != null) {
        await safeComplete(await _finalizeSuccess(
          resp: resp,
          row: row,
          selectedNumId: selectedNumId,
          srcNum: srcNum,
          amount: amount,
          formFees: formFees,
          isExternalWallet: isExternalWallet,
          applyCredit: applyCredit,
          adminNotes: adminNotes,
          bufferedFee: bufferedFee,
          distribution: distribution,
          onSuccessUi: onSuccessUi,
        ));
      } else if (resp.status == UssdStatus.error) {
        await handleFailure(resp.message);
      }
    });

    try {
      await UssdService.runVodafoneCashTransfer(
        phoneNumber: row.request.vfPhoneNumber,
        amount: amount,
        sessionId: expectedSessionId,
      );
    } catch (e) {
      await handleFailure('USSD start failed: $e');
    }

    return completer.future;
  }

  static Future<RetailerUssdRunResult> _finalizeSuccess({
    required UssdResponse resp,
    required RetailerPortalRequestRow row,
    required String selectedNumId,
    required MobileNumber srcNum,
    required double amount,
    required double formFees,
    required bool isExternalWallet,
    required bool applyCredit,
    required String adminNotes,
    required double? bufferedFee,
    required DistributionProvider distribution,
    void Function()? onSuccessUi,
  }) async {
    try {
      final file = File(resp.screenshotPath!);
      final ref = FirebaseStorage.instance.ref().child('assignment_proofs/${row.request.id}_ussd.jpg');
      await ref.putFile(file);
      final downloadUrl = await ref.getDownloadURL();

      final finalFee = (bufferedFee ?? formFees).clamp(0.0, double.infinity);
      final chargeRetailer = bufferedFee != null ? finalFee > 1.0 : isExternalWallet;

      await distribution.processRetailerRequest(
        portalUserUid: row.portalUserUid,
        requestId: row.request.id,
        status: 'COMPLETED',
        proofImageUrl: downloadUrl,
        adminNotes: 'Auto-USSD: ${resp.message}. $adminNotes',
        retailerId: row.request.retailerId,
        fromVfNumberId: selectedNumId,
        fromVfPhone: srcNum.phoneNumber,
        amount: amount,
        fees: finalFee,
        chargeFeesToRetailer: chargeRetailer,
        applyCredit: applyCredit,
      );

      onSuccessUi?.call();
      return const RetailerUssdRunResult(success: true, message: 'ok', didUnlock: false);
    } catch (e) {
      return RetailerUssdRunResult(success: false, message: 'Finalize failed: $e', didUnlock: false);
    }
  }
}
