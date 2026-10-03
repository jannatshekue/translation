import 'package:shared_preferences/shared_preferences.dart';

import 'database_service.dart';
import 'settings_service.dart';

/// The everyday phrases every person gets on first launch, plus a few that
/// only make sense for one profile. They are ordinary saved phrases once
/// created — editable and deletable like any other — and are only ever
/// created once, so deleting one never brings it back.
class StarterPhrases {
  StarterPhrases._();

  // v3: earlier versions skipped seeding whenever any phrase existed (v1), or
  // topped up without putting the essentials in order (v2). v3 does both.
  static const _seededKey = 'starter_phrases_seeded_v3';

  /// Most important first (this is the order they appear on Home).
  static const general = [
    'Please help me.',
    'Pardon?',
    'Excuse me.',
    "I'm sorry.",
    'Thank you.',
    'Please.',
    'Yes.',
    'No.',
    'Hello.',
    'Please say that again.',
    'Please speak slowly.',
    'Please write it down for me.',
    "I don't understand.",
    'Wait a moment, please.',
    'Where is the toilet?',
    'I need water.',
    'I need a doctor.',
    'Please call an ambulance.',
    'Please call the police.',
    'I am lost.',
    "You're welcome.",
    'Goodbye.',
  ];

  /// Added once when someone picks the profile (first launch or later).
  static const forSpeech = [
    'Hello. I cannot speak, please be patient with me.',
    'Please wait while I type.',
  ];

  static const forHearing = [
    'I am deaf. Please face me and speak slowly.',
    'Please write it down, I cannot hear you.',
  ];

  /// Phrases the Emergency tab speaks aloud in one tap. Fixed (not saved
  /// phrases) so they are always there, whatever has been edited or deleted.
  static const emergencySpoken = [
    'Help me, please.',
    'Please call an ambulance.',
    'Please call the police.',
    'I need a doctor.',
    'I am lost.',
  ];

  /// Makes sure the everyday phrases exist, once, in order of importance.
  /// Phrases the person already has are kept (an essential they already have
  /// — ignoring capitals and the full stop — is moved into place rather than
  /// duplicated), and only the missing ones are added.
  static Future<void> seedIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_seededKey) ?? false) return;
      final existing = await DatabaseService.instance.getSavedPhrases();
      final byText = {for (final phrase in existing) _normalize(phrase.text): phrase};

      // Newest-first listing: the most important phrase gets the latest time.
      final now = DateTime.now();
      for (var i = 0; i < general.length; i++) {
        final when = now.subtract(Duration(milliseconds: i));
        final match = byText[_normalize(general[i])];
        if (match != null) {
          await DatabaseService.instance.setSavedPhraseTime(match.id, when);
        } else {
          await DatabaseService.instance.insertSavedPhrase(general[i], createdAt: when);
        }
      }
      await prefs.setBool(_seededKey, true);
    } catch (_) {
      // Phrases are a convenience; never block the app if storage fails.
    }
  }

  static String _normalize(String text) =>
      text.trim().toLowerCase().replaceAll(RegExp(r'[.!]+$'), '');

  /// Adds the profile-specific extras once per profile.
  static Future<void> seedForProfile(UserProfile profile) async {
    final extras = switch (profile) {
      UserProfile.speechImpaired => forSpeech,
      UserProfile.hearingImpaired => forHearing,
      UserProfile.normal => const <String>[],
    };
    if (extras.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'starter_extras_${profile.name}';
      if (prefs.getBool(key) ?? false) return;
      await _insertInOrder(extras);
      await prefs.setBool(key, true);
    } catch (_) {
      // See above.
    }
  }

  /// Saved phrases list newest-first, so give the first phrase the latest
  /// timestamp and each following one a millisecond earlier.
  static Future<void> _insertInOrder(List<String> phrases) async {
    final now = DateTime.now();
    for (var i = 0; i < phrases.length; i++) {
      await DatabaseService.instance.insertSavedPhrase(
        phrases[i],
        createdAt: now.subtract(Duration(milliseconds: i)),
      );
    }
  }
}
