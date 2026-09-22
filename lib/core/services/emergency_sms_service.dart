import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Android-only emergency alert: gets the current GPS position and hands it,
/// with a pre-set message, to native code over a MethodChannel for sending
/// via SmsManager. iOS has no path here — see project notes (SMS sending
/// cannot be triggered programmatically on iOS).
///
/// Native counterpart: android/app/src/main/kotlin/.../MainActivity.kt.
class EmergencySmsService {
  EmergencySmsService._internal();

  static final EmergencySmsService instance = EmergencySmsService._internal();

  static const MethodChannel _channel = MethodChannel('translation/emergency_sms');

  Future<Position> _getCurrentLocation() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Location permission denied.');
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Location services are disabled.');
    }
    return Geolocator.getCurrentPosition();
  }

  /// Sends the emergency message plus current GPS coordinates to every
  /// number in [phoneNumbers]. Fetches location once and reuses it for all
  /// recipients rather than re-requesting per contact.
  Future<void> sendAlert({
    required List<String> phoneNumbers,
    required String message,
  }) async {
    if (phoneNumbers.isEmpty) {
      throw ArgumentError('At least one phone number is required.');
    }

    final smsStatus = await Permission.sms.request();
    if (!smsStatus.isGranted) {
      throw StateError('SMS permission denied.');
    }

    final position = await _getCurrentLocation();
    final fullMessage =
        '$message\nLocation: https://maps.google.com/?q=${position.latitude},${position.longitude}';

    for (final phoneNumber in phoneNumbers) {
      await _channel.invokeMethod<void>('sendSms', {
        'phoneNumber': phoneNumber,
        'message': fullMessage,
      });
    }
  }
}
