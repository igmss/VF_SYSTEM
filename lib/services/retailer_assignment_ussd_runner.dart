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

    MobileNumber srcNum;
    try {
      srcNum = app.mobileNumbers.firstWhere((n) => n.id == selectedNumId);
    } catch (_) {
      return const RetailerUssdRunResult(success: false, message: 'VF number not found', didUnlock: false);
    }

    if (!hasLikelySufficientBalance(
      vfNumber: srcNum,
      amount: amount,
      isExternalWallet: isExternalWallet,
    )) {
      return RetailerUssdRunResult(
        success: false,
        message: 'Insufficient VF balance for this transfer (including fees).',
        didUnlock: false,
      );
    }

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

    Future<void> cleanupSubsOnly() async {
      timeoutTimer?.cancel();
      await sub?.cancel();
    }

    Future<void> unlockQuiet() async {
      try {
        await portal.unlockRequestAdmin(portalUserUid: row.portalUserUid, requestId: row.request.id);
      } catch (_) {}
    }

    // Timeouts must cover: pre-PIN wait + post-success wait + screenshot + upload (see Android USSD delays).
    timeoutTimer = Timer(const Duration(minutes: 5), () async {
      if (finished) return;
      await cleanupSubsOnly();
      await unlockQuiet();
      await safeComplete(const RetailerUssdRunResult(
        success: false,
        message: 'USSD timed out; request returned to pending.',
        didUnlock: true,
      ));
    });

    // Subscribe BEFORE lock + dial so we never miss SUCCESS/SCREENSHOT for this session.
    sub = UssdService.onUpdate.listen((resp) async {
      if (finished) return;

      if (resp.sessionId != expectedSessionId) {
        return;
      }

      if (resp.extractedFee != null) {
        bufferedFee = resp.extractedFee;
      }

      if (resp.status == UssdStatus.success && resp.screenshotPath != null) {
        await cleanupSubsOnly();
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
          await safeComplete(const RetailerUssdRunResult(
            success: true,
            message: 'ok',
            didUnlock: false,
          ));
        } catch (e) {
          // Do NOT unlock: money may have already moved on the phone; retrying would double-send.
          await safeComplete(RetailerUssdRunResult(
            success: false,
            message: 'Finalize failed: $e',
            didUnlock: false,
          ));
        }
        return;
      }

      if (resp.status == UssdStatus.error) {
        await cleanupSubsOnly();
        await unlockQuiet();
        await safeComplete(RetailerUssdRunResult(
          success: false,
          message: resp.message,
          didUnlock: true,
        ));
      }
    });

    try {
      await portal.lockRequestAdmin(
        portalUserUid: row.portalUserUid,
        requestId: row.request.id,
        adminUid: adminUid,
      );
    } catch (e) {
      await cleanupSubsOnly();
      await safeComplete(RetailerUssdRunResult(success: false, message: 'Could not lock request: $e', didUnlock: false));
      return completer.future;
    }

    try {
      await UssdService.runVodafoneCashTransfer(
        phoneNumber: row.request.vfPhoneNumber,
        amount: amount,
        sessionId: expectedSessionId,
      );
    } catch (e) {
      await cleanupSubsOnly();
      await unlockQuiet();
      await safeComplete(RetailerUssdRunResult(
        success: false,
        message: 'USSD start failed: $e',
        didUnlock: true,
      ));
      return completer.future;
    }

    return completer.future;
  }
}
