import 'package:flutter/foundation.dart';

/// Tiny change signals so a screen that shows a summary of some data (Home's
/// quick phrases and learning ring) refreshes the moment that data changes
/// elsewhere, instead of showing stale numbers until it's rebuilt.
class AppEvents {
  AppEvents._();

  static final ValueNotifier<int> phrasesChanged = ValueNotifier<int>(0);
  static final ValueNotifier<int> progressChanged = ValueNotifier<int>(0);

  static void notifyPhrasesChanged() => phrasesChanged.value++;
  static void notifyProgressChanged() => progressChanged.value++;
}
