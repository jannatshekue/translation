import 'package:flutter/services.dart';

class PickedContact {
  final String name;
  final String number;

  const PickedContact({required this.name, required this.number});
}

/// Opens the phone's own contact picker and returns the chosen contact's
/// name and number. Uses the system picker (Android ACTION_PICK) rather than
/// reading the whole address book, so the app needs no contacts permission
/// and only ever sees the one contact the person taps.
///
/// Native counterpart: android/app/src/main/kotlin/.../MainActivity.kt.
class ContactPickerService {
  ContactPickerService._internal();

  static final ContactPickerService instance = ContactPickerService._internal();

  static const MethodChannel _channel = MethodChannel('translation/contacts');

  /// Returns null if the person backed out without choosing. Throws a
  /// [StateError] with a readable message if the phone has no contacts app.
  Future<PickedContact?> pickContact() async {
    try {
      final result = await _channel.invokeMapMethod<String, String>('pickContact');
      if (result == null) return null;
      final number = result['number'];
      if (number == null || number.trim().isEmpty) return null;
      return PickedContact(name: result['name'] ?? '', number: number);
    } on PlatformException catch (e) {
      throw StateError(e.message ?? 'Could not open the phonebook.');
    } on MissingPluginException {
      throw StateError('Choosing from the phonebook is only available on Android.');
    }
  }
}
