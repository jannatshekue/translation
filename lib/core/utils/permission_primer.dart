import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Explains why a permission is needed before the OS dialog fires, instead
/// of surprising the user with a bare system prompt. Skips the explanation
/// entirely if the permission is already granted.
class PermissionPrimer {
  PermissionPrimer._();

  static Future<bool> requestWithRationale(
    BuildContext context, {
    required Permission permission,
    required String title,
    required String message,
  }) async {
    if (await permission.status.isGranted) return true;
    if (!context.mounted) return false;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (proceed != true) return false;

    final result = await permission.request();
    return result.isGranted;
  }
}
