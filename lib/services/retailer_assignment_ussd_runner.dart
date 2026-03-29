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

    int retryCount = 0;
    double? baselineBalance;

    try {
      await portal.lockRequestAdmin(
        portalUserUid: row.portalUserUid,
        requestId: row.request.id,
        adminUid: adminUid,
      );
    } catch (e) {
      return RetailerUssdRunResult(success: false, message: 'Could not lock request: $e', didUnlock: false);
    }

    Future<double?> getBalance() async {
      final sessionId = const Uuid().v4();
      final completer = Completer<double?>();
      StreamSubscription? sub;
      Timer? timer;

      sub = UssdService.onUpdate.listen((resp) {
        if (resp.sessionId == sessionId && resp.status == UssdStatus.balanceDetected) {
          timer?.cancel();
          sub?.cancel();
          completer.complete(resp.extractedBalance);
        } else if (resp.sessionId == sessionId && resp.status == UssdStatus.error) {
          timer?.cancel();
          sub?.cancel();
          completer.complete(null);
        }
      });

      timer = Timer(const Duration(seconds: 45), () {
        sub?.cancel();
        if (!completer.isCompleted) completer.complete(null);
      });

      try {
        await UssdService.runVodafoneCashBalanceCheck(sessionId: sessionId);
      } catch (_) {
        timer.cancel();
        sub.cancel();
        completer.complete(null);
      }

      return completer.future;
    }

    baselineBalance = await getBalance();
    if (baselineBalance == null) {
      await portal.unlockRequestAdmin(portalUserUid: row.portalUserUid, requestId: row.request.id);
      return const RetailerUssdRunResult(
        success: false,
        message: 'Could not fetch baseline balance. Aborting for safety.',
        didUnlock: true,
      );
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
      baselineBalance: baselineBalance,
      retryCount: retryCount,
      getBalance: getBalance,
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
    required double baselineBalance,
    required int retryCount,
    required Future<double?> Function() getBalance,
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

      // If we fail/timeout, we must check the balance before retrying or giving up.
      final currentBalance = await getBalance();
      if (currentBalance != null) {
        if ((currentBalance - baselineBalance).abs() < 1.0) {
          // Balance is same, SAFE TO RETRY if we haven't exceeded max retries
          if (retryCount < _maxRetries) {
            finished = true;
            timeoutTimer?.cancel();
            await sub?.cancel();

            final r = await _runTransferLoop(
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
              baselineBalance: baselineBalance,
              retryCount: retryCount + 1,
              getBalance: getBalance,
              onSuccessUi: onSuccessUi,
            );
            if (!completer.isCompleted) completer.complete(r);
            return;
          } else {
            // Max retries reached, unlock and fail.
            try {
              await portal.unlockRequestAdmin(portalUserUid: row.portalUserUid, requestId: row.request.id);
            } catch (_) {}
            await safeComplete(RetailerUssdRunResult(success: false, message: 'Max retries reached: $errorMsg', didUnlock: true));
          }
        } else {
          // Balance changed! Money moved but we didn't get success. MOVE TO MANUAL_REVIEW.
          try {
            await portal.updateRequestAdmin(
              portalUserUid: row.portalUserUid,
              requestId: row.request.id,
              updates: {
                'status': 'MANUAL_REVIEW',
                'adminNotes': 'Balance dropped from $baselineBalance to $currentBalance but USSD failed/timed out. DO NOT RETRY.',
              },
            );
          } catch (_) {}
          await safeComplete(const RetailerUssdRunResult(success: false, message: 'Balance dropped! Moved to MANUAL_REVIEW.', didUnlock: false));
        }
      } else {
        // Balance check failed after transfer failure. Very dangerous. MANUAL_REVIEW.
        try {
          await portal.updateRequestAdmin(
            portalUserUid: row.portalUserUid,
            requestId: row.request.id,
            updates: {
              'status': 'MANUAL_REVIEW',
              'adminNotes': 'USSD failed/timed out and balance check also failed. Manual verification required.',
            },
          );
        } catch (_) {}
        await safeComplete(const RetailerUssdRunResult(success: false, message: 'Verification failed. Moved to MANUAL_REVIEW.', didUnlock: false));
      }
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
