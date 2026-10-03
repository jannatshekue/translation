import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Android-only emergency alert: gets the current GPS position (if it can) and hands it,
/// with a pre-set message, to native code over a MethodChannel for sending
/// via SmsManager. iOS has no path here — see project notes (SMS sending
/// cannot be triggered programmatically on iOS).
///
/// Native counterpart: android/app/src/main/kotlin/.../MainActivity.kt.
class EmergencySmsService {
  EmergencySmsService._internal();

  static final EmergencySmsService instance = EmergencySmsService._internal();

  static const MethodChannel _channel = MethodChannel('translation/emergency_sms');

  /// Best-effort location: a fresh fix if possible, else the last known one,
  /// else null. Never throws — in an emergency a missing location must not
  /// stop the alert itself from going out.
  Future<Position?> _tryGetLocation() async {
    try {
      // Only uses location that was already allowed; asking is the screen's
      // job (once, at the moment of sending), never repeated here.
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      if (await Geolocator.isLocationServiceEnabled()) {
        try {
          return await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(timeLimit: Duration(seconds: 10)),
          );
        } catch (_) {
          // Timed out or failed — fall through to the last known fix.
        }
      }
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  String _describeError(Object e) {
    if (e is PlatformException) return e.message ?? e.code;
    return e.toString();
  }

  /// Sends the emergency message (plus the current GPS link when available)
  /// to every number in [phoneNumbers], one at a time, and reports what
  /// happened to each. A failure for one number never stops the others — the
  /// caller gets a [SmsAlertReport] listing who got it and who didn't, and
  /// why. Throws only if SMS permission is denied (nothing can be sent).
  Future<SmsAlertReport> sendAlert({
    required List<String> phoneNumbers,
    required String message,
  }) async {
    if (phoneNumbers.isEmpty) {
      throw ArgumentError('At least one phone number is required.');
    }

    if (!await Permission.sms.status.isGranted) {
      throw StateError('SMS permission is needed for this feature.');
    }

    final position = await _tryGetLocation();
    final fullMessage = position == null
        ? message
        : '$message\nLocation: https://maps.google.com/?q=${position.latitude},${position.longitude}';

    final sent = <String>[];
    final failed = <String, String>{};
    for (final phoneNumber in phoneNumbers.toSet()) {
      try {
        await _channel.invokeMethod<void>('sendSms', {
          'phoneNumber': phoneNumber,
          'message': fullMessage,
        });
        sent.add(phoneNumber);
      } catch (e) {
        failed[phoneNumber] = _describeError(e);
      }
    }
    return SmsAlertReport(sent: sent, failed: failed, locationIncluded: position != null);
  }
}

/// Outcome of one [EmergencySmsService.sendAlert] call, per phone number.
class SmsAlertReport {
  final List<String> sent;

  /// Number -> plain-language reason it failed.
  final Map<String, String> failed;
  final bool locationIncluded;

  const SmsAlertReport({required this.sent, required this.failed, required this.locationIncluded});

  bool get allSucceeded => failed.isEmpty && sent.isNotEmpty;
  bool get anySucceeded => sent.isNotEmpty;
}
