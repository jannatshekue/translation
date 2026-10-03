import 'package:flutter/material.dart';

import '../../routes/app_routes.dart';
import '../services/settings_service.dart';
import '../services/starter_phrases.dart';
import 'app_tools.dart';

/// What the app does differently for each accessibility profile. Nothing is
/// ever hidden — every tool stays reachable — but the profile decides what is
/// put first, what the one-tap hero action on Home is, how the Voice screen
/// opens, and which accessibility defaults are switched on.
class ProfileExperience {
  final UserProfile profile;

  /// Short name shown in the app ("Deaf or hard of hearing").
  final String label;

  /// One sentence on what this profile changes, shown in onboarding/Settings.
  final String blurb;

  /// Bullet list of the concrete differences, shown in onboarding.
  final List<String> perks;
  final IconData icon;

  // Home hero (the single most useful action for this person).
  final String heroTitle;
  final String heroSubtitle;
  final String heroCta;
  final IconData heroIcon;
  final void Function(BuildContext context) openHero;

  /// Order in which tools are listed on Home and Communicate.
  final List<AppTool> toolOrder;

  /// Tools shown as "For you" in the lists.
  final Set<AppTool> recommended;

  /// Which half of the Voice screen opens by default.
  final VoiceMode voiceMode;

  /// Whether Home shows one-tap quick phrases by default (speak without
  /// typing). Anyone can switch it on or off in Settings.
  final bool showQuickPhrases;

  const ProfileExperience({
    required this.profile,
    required this.label,
    required this.blurb,
    required this.perks,
    required this.icon,
    required this.heroTitle,
    required this.heroSubtitle,
    required this.heroCta,
    required this.heroIcon,
    required this.openHero,
    required this.toolOrder,
    required this.recommended,
    required this.voiceMode,
    required this.showQuickPhrases,
  });

  static ProfileExperience of(UserProfile? profile) {
    switch (profile) {
      case UserProfile.hearingImpaired:
        return _hearing;
      case UserProfile.speechImpaired:
        return _speech;
      case UserProfile.normal:
      case null:
        return _everyone;
    }
  }

  static final _everyone = ProfileExperience(
    profile: UserProfile.normal,
    label: 'Hearing & speaking',
    blurb: 'Talk across languages and learn sign language.',
    perks: const [
      'Home opens on Conversation mode',
      'Translate between two people, on one phone or two',
      'Learn signs front and centre',
    ],
    icon: Icons.people_outline,
    heroTitle: 'Start a conversation',
    heroSubtitle: 'Translate between two people, face to face',
    heroCta: 'Start talking',
    heroIcon: Icons.forum_outlined,
    openHero: (context) => AppTool.conversation.open(context),
    toolOrder: const [
      AppTool.conversation,
      AppTool.connectDevices,
      AppTool.signRecognition,
      AppTool.learn,
      AppTool.speechToText,
      AppTool.textToSpeech,
      AppTool.savedPhrases,
      AppTool.customSigns,
    ],
    recommended: const {AppTool.conversation, AppTool.learn},
    voiceMode: VoiceMode.listen,
    showQuickPhrases: false,
  );

  static final _hearing = ProfileExperience(
    profile: UserProfile.hearingImpaired,
    label: 'Deaf or hard of hearing',
    blurb: 'See speech as text, and get visual and vibration alerts.',
    perks: const [
      'Home opens on Live captions — one tap to start',
      'Captions shown in large text',
      'Flash and vibration alerts switched on',
      'Quick phrases on Home, like "I am deaf, please write it down"',
    ],
    icon: Icons.hearing_disabled_outlined,
    heroTitle: 'Live captions',
    heroSubtitle: 'See what people say, as they say it',
    heroCta: 'Start captions',
    heroIcon: Icons.closed_caption_outlined,
    openHero: (context) {
      SettingsService.instance.hapticTap();
      Navigator.of(context).pushNamed(
        AppRoutes.voiceTranslation,
        arguments: const VoiceScreenArgs(mode: VoiceMode.listen, autoListen: true),
      );
    },
    toolOrder: const [
      AppTool.speechToText,
      AppTool.conversation,
      AppTool.connectDevices,
      AppTool.signRecognition,
      AppTool.savedPhrases,
      AppTool.learn,
      AppTool.textToSpeech,
      AppTool.customSigns,
    ],
    recommended: const {AppTool.speechToText, AppTool.conversation},
    voiceMode: VoiceMode.listen,
    showQuickPhrases: true,
  );

  static final _speech = ProfileExperience(
    profile: UserProfile.speechImpaired,
    label: 'Cannot speak',
    blurb: 'Let your phone speak for you — by typing, phrases or signs.',
    perks: const [
      'Home opens on Speak for me — type and it talks',
      'One-tap quick phrases right on Home',
      'Everyday phrases saved for you: Pardon?, Excuse me, Thank you…',
    ],
    icon: Icons.record_voice_over_outlined,
    heroTitle: 'Speak for me',
    heroSubtitle: 'Type a message and your phone says it aloud',
    heroCta: 'Start typing',
    heroIcon: Icons.record_voice_over_outlined,
    openHero: (context) {
      SettingsService.instance.hapticTap();
      Navigator.of(context).pushNamed(
        AppRoutes.voiceTranslation,
        arguments: const VoiceScreenArgs(mode: VoiceMode.speak, autoFocusTyping: true),
      );
    },
    toolOrder: const [
      AppTool.textToSpeech,
      AppTool.savedPhrases,
      AppTool.signRecognition,
      AppTool.connectDevices,
      AppTool.conversation,
      AppTool.customSigns,
      AppTool.learn,
      AppTool.speechToText,
    ],
    recommended: const {AppTool.textToSpeech, AppTool.savedPhrases, AppTool.signRecognition},
    voiceMode: VoiceMode.speak,
    showQuickPhrases: true,
  );

  /// Applies a profile choice. [firstRun] is true during onboarding, where
  /// accessibility defaults (alerts, text size) are switched on; later
  /// switches keep the person's own toggles. Also makes sure the starter
  /// phrases exist (plus this profile's extras, once).
  static Future<void> choose(UserProfile profile, {required bool firstRun}) async {
    // Seed first: setting the profile makes Home rebuild at once, and it
    // should find the phrases already there.
    await StarterPhrases.seedIfNeeded();
    await StarterPhrases.seedForProfile(profile);
    await SettingsService.instance.setUserProfile(profile, applyDefaults: firstRun);
  }
}
