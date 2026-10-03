import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// How the app asks for permissions — deliberately minimal:
///
///  * Only when a feature that needs the permission is actually being used,
///    never earlier.
///  * Only Android's own prompt. The app adds no explanation box of its own.
///  * A refusal is final for that attempt: the feature does not run and a
///    short message says why. No second box, no Settings page, no re-asking.
///    The person is asked again only the next time they use the feature.
class AppPermissions {
  AppPermissions._();

  /// "Camera permission is needed for this feature."
  static String neededMessage(Permission permission) =>
      '${_nameOf(permission)} permission is needed for this feature.';

  /// Returns true if [permission] is granted, asking Android's prompt first
  /// if it is not. On refusal returns false and (unless [announceDenial] is
  /// false, for screens that show their own message) shows a short message.
  static Future<bool> ensure(
    BuildContext context,
    Permission permission, {
    bool announceDenial = true,
  }) {
    return ensureAll(context, required: [permission], announceDenial: announceDenial);
  }

  /// Like [ensure] for a feature that needs several permissions together.
  /// Returns true only if every one of [required] is granted; [optional] ones
  /// are asked in the same prompt but never decide the result.
  static Future<bool> ensureAll(
    BuildContext context, {
    required List<Permission> required,
    List<Permission> optional = const [],
    bool announceDenial = true,
  }) async {
    if (await _allGranted(required)) return true;

    final toAsk = <Permission>[];
    for (final p in [...required, ...optional]) {
      if (!await p.status.isGranted) toAsk.add(p);
    }
    await toAsk.request();

    if (await _allGranted(required)) return true;

    if (announceDenial && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(neededMessage(required.first))),
      );
    }
    return false;
  }

  static Future<bool> _allGranted(List<Permission> permissions) async {
    for (final p in permissions) {
      if (!await p.status.isGranted) return false;
    }
    return true;
  }

  static String _nameOf(Permission permission) {
    if (permission == Permission.camera) return 'Camera';
    if (permission == Permission.microphone) return 'Microphone';
    if (permission == Permission.sms) return 'SMS';
    if (permission == Permission.location || permission == Permission.locationWhenInUse) {
      return 'Location';
    }
    if (permission == Permission.bluetoothScan ||
        permission == Permission.bluetoothAdvertise ||
        permission == Permission.bluetoothConnect ||
        permission == Permission.nearbyWifiDevices) {
      return 'Nearby devices';
    }
    return 'This';
  }
}
