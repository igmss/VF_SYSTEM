import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';

enum UssdStatus { idle, dialing, waitingPin, feePreview, balanceDetected, pinEntered, success, error }

class UssdResponse {
  final UssdStatus status;
  final String message;
  final String? screenshotPath;
  final double? extractedFee;
  final double? extractedBalance; // New field
  final String? sessionId;

  UssdResponse({
    required this.status,
    required this.message,
    this.screenshotPath,
    this.extractedFee,
    this.extractedBalance,
    this.sessionId,
  });
}

/// Android-only: [MainActivity] dials USSD via [UssdAccessibilityService] and sends events here.
///
/// Typical sequence: optional `FEE_DETECTED:x` (fee line on pre-PIN screen), `STATUS:WAITING_PIN_MS:8000`,
/// `SUCCESS:...` (optional `| FEE:x`) then `SCREENSHOT:/path`.
/// The assignment UI waits for an event with [UssdResponse.screenshotPath] set before uploading.
/// If the accessibility service never sends `SCREENSHOT:`, the request stays PROCESSING until timeout.
class UssdService {
  static const _methodChannel = MethodChannel('com.vodafone.vodafone_cash_tracker/ussd_method');
  static const _eventChannel = EventChannel('com.vodafone.vodafone_cash_tracker/ussd_event');
  static const _storage = FlutterSecureStorage();
  static const _pinKey = 'ussd_admin_pin';

  static final _statusController = StreamController<UssdResponse>.broadcast();
  static Stream<UssdResponse> get onUpdate => _statusController.stream;

  static void init() {
    _eventChannel.receiveBroadcastStream().listen((event) {
      var msg = event.toString();
      String? sid;

      // Handle USSD2 format: USSD2:<sessionId>:<rawMessage>
      if (msg.startsWith('USSD2:')) {
        final parts = msg.split(':');
        if (parts.length >= 3) {
          sid = parts[1];
          msg = parts.sublist(2).join(':');
        }
      }

      if (msg.startsWith('STATUS:PIN_ENTERED')) {
        _statusController.add(UssdResponse(
          status: UssdStatus.pinEntered,
          message: 'PIN entered automatically.',
          sessionId: sid,
        ));
      } else if (msg.startsWith('STATUS:WAITING_PIN_MS:')) {
        _statusController.add(UssdResponse(
          status: UssdStatus.waitingPin,
          message: msg.replaceFirst('STATUS:', '').trim(),
          sessionId: sid,
        ));
      } else if (msg.startsWith('FEE_DETECTED:')) {
        final raw = msg.replaceFirst('FEE_DETECTED:', '').trim();
        final v = double.tryParse(raw);
        _statusController.add(UssdResponse(
          status: UssdStatus.feePreview,
          message: 'Fee from USSD screen',
          extractedFee: v,
          sessionId: sid,
        ));
      } else if (msg.startsWith('BALANCE_DETECTED:')) {
        final raw = msg.replaceFirst('BALANCE_DETECTED:', '').trim();
        final v = double.tryParse(raw);
        _statusController.add(UssdResponse(
          status: UssdStatus.balanceDetected,
          message: 'Balance from USSD screen',
          extractedBalance: v,
          sessionId: sid,
        ));
      } else if (msg.startsWith('SUCCESS:')) {
        var cleanMsg = msg.replaceFirst('SUCCESS:', '').trim();
        double? fee;
        if (cleanMsg.contains('| FEE:')) {
          final parts = cleanMsg.split('| FEE:');
          cleanMsg = parts[0].trim();
          fee = double.tryParse(parts[1].trim());
        }
        _statusController.add(UssdResponse(
          status: UssdStatus.success,
          message: cleanMsg,
          extractedFee: fee,
          sessionId: sid,
        ));
      } else if (msg.startsWith('ERROR:')) {
        _statusController.add(UssdResponse(
          status: UssdStatus.error,
          message: msg.replaceFirst('ERROR:', '').trim(),
          sessionId: sid,
        ));
      } else if (msg.startsWith('SCREENSHOT:')) {
        final path = msg.replaceFirst('SCREENSHOT:', '').trim();
        _statusController.add(UssdResponse(
          status: UssdStatus.success,
          message: 'Screenshot captured.',
          screenshotPath: path,
          sessionId: sid,
        ));
      }
    });
  }

  static Future<void> savePin(String pin) async {
    await _storage.write(key: _pinKey, value: pin);
  }

  static Future<String?> getPin() async {
    return await _storage.read(key: _pinKey);
  }

  static Future<bool> isAccessibilityEnabled() async {
    // This is hard to check directly, but we can try to run a dummy command or 
    // just rely on the user enabling it.
    return true; 
  }

  static Future<void> runVodafoneCashBalanceCheck({
    required String sessionId,
  }) async {
    final status = await Permission.phone.request();
    if (!status.isGranted) {
      _statusController.add(UssdResponse(
        status: UssdStatus.error,
        message: 'Phone permission denied.',
        sessionId: sessionId,
      ));
      return;
    }

    final pin = await getPin();
    if (pin == null || pin.isEmpty) {
      _statusController.add(UssdResponse(
        status: UssdStatus.error,
        message: 'USSD PIN not set. Please set it in settings.',
        sessionId: sessionId,
      ));
      return;
    }

    const code = '*9*13#';
    _statusController.add(UssdResponse(
      status: UssdStatus.dialing,
      message: 'Dialing $code...',
      sessionId: sessionId,
    ));

    try {
      await _methodChannel.invokeMethod('runUssd', {
        'code': code,
        'pin': pin,
        'sessionId': sessionId,
      });
    } on PlatformException catch (e) {
      _statusController.add(UssdResponse(
        status: UssdStatus.error,
        message: 'Failed to run USSD: ${e.message}',
        sessionId: sessionId,
      ));
    }
  }

  static Future<void> runVodafoneCashTransfer({
    required String phoneNumber,
    required double amount,
    required String sessionId,
  }) async {
    final status = await Permission.phone.request();
    if (!status.isGranted) {
      _statusController.add(UssdResponse(
        status: UssdStatus.error,
        message: 'Phone permission denied.',
        sessionId: sessionId,
      ));
      return;
    }

    final pin = await getPin();
    if (pin == null || pin.isEmpty) {
      _statusController.add(UssdResponse(
        status: UssdStatus.error,
        message: 'USSD PIN not set. Please set it in settings.',
        sessionId: sessionId,
      ));
      return;
    }

    final code = '*9*7*$phoneNumber*${amount.toInt()}#';
    _statusController.add(UssdResponse(
      status: UssdStatus.dialing,
      message: 'Dialing $code...',
      sessionId: sessionId,
    ));

    try {
      await _methodChannel.invokeMethod('runUssd', {
        'code': code,
        'pin': pin,
        'sessionId': sessionId,
      });
    } on PlatformException catch (e) {
      _statusController.add(UssdResponse(
        status: UssdStatus.error,
        message: 'Failed to run USSD: ${e.message}',
        sessionId: sessionId,
      ));
    }
  }
}
