import 'package:flutter/material.dart';

import '../../routes/app_routes.dart';
import '../services/settings_service.dart';

/// Which half of the Voice screen to open on.
enum VoiceMode { listen, speak }

/// Arguments for the Voice screen route.
class VoiceScreenArgs {
  final VoiceMode mode;

  /// Start the microphone straight away (live captions in one tap).
  final bool autoListen;

  /// Put the cursor in the text box straight away (speak-for-me in one tap).
  final bool autoFocusTyping;

  const VoiceScreenArgs({
    required this.mode,
    this.autoListen = false,
    this.autoFocusTyping = false,
  });
}

/// Every feature the app offers, described once. Home, Communicate and the
/// profile logic all read from here so titles, icons and destinations never
/// drift apart between screens.
enum AppTool {
  signRecognition,
  speechToText,
  textToSpeech,
  conversation,
  connectDevices,
  savedPhrases,
  learn,
  customSigns,
}

extension AppToolInfo on AppTool {
  String get title => switch (this) {
        AppTool.signRecognition => 'Sign recognition',
        AppTool.speechToText => 'Live captions',
        AppTool.textToSpeech => 'Type to speak',
        AppTool.conversation => 'Conversation mode',
        AppTool.connectDevices => 'Connect devices',
        AppTool.savedPhrases => 'Saved phrases',
        AppTool.learn => 'Learn signs',
        AppTool.customSigns => 'My custom signs',
      };

  String get subtitle => switch (this) {
        AppTool.signRecognition => 'Point the camera at a sign — see and hear what it means',
        AppTool.speechToText => 'Turn what you hear into text, as it is said',
        AppTool.textToSpeech => 'Type a message and let your phone say it aloud',
        AppTool.conversation => 'Translate between two people sharing one phone',
        AppTool.connectDevices => 'Talk across two phones, no internet needed',
        AppTool.savedPhrases => 'Your own phrases, spoken in one tap',
        AppTool.learn => 'Short lessons with camera practice',
        AppTool.customSigns => 'Teach the app signs of your own',
      };

  IconData get icon => switch (this) {
        AppTool.signRecognition => Icons.sign_language,
        AppTool.speechToText => Icons.closed_caption_outlined,
        AppTool.textToSpeech => Icons.record_voice_over_outlined,
        AppTool.conversation => Icons.forum_outlined,
        AppTool.connectDevices => Icons.bluetooth_connected,
        AppTool.savedPhrases => Icons.bookmark_border,
        AppTool.learn => Icons.school_outlined,
        AppTool.customSigns => Icons.add_reaction_outlined,
      };

  Color get color => switch (this) {
        AppTool.signRecognition => const Color(0xFF233E8B),
        AppTool.speechToText => const Color(0xFF0F766E),
        AppTool.textToSpeech => const Color(0xFF6D28D9),
        AppTool.conversation => const Color(0xFFB45309),
        AppTool.connectDevices => const Color(0xFF0369A1),
        AppTool.savedPhrases => const Color(0xFFBE185D),
        AppTool.learn => const Color(0xFF4D7C0F),
        AppTool.customSigns => const Color(0xFFC2410C),
      };

  /// Opens this tool on top of the current screen.
  void open(BuildContext context) {
    SettingsService.instance.hapticTap();
    final navigator = Navigator.of(context);
    switch (this) {
      case AppTool.signRecognition:
        navigator.pushNamed(AppRoutes.signRecognition);
      case AppTool.speechToText:
        navigator.pushNamed(
          AppRoutes.voiceTranslation,
          arguments: const VoiceScreenArgs(mode: VoiceMode.listen),
        );
      case AppTool.textToSpeech:
        navigator.pushNamed(
          AppRoutes.voiceTranslation,
          arguments: const VoiceScreenArgs(mode: VoiceMode.speak),
        );
      case AppTool.conversation:
        navigator.pushNamed(AppRoutes.conversationMode);
      case AppTool.connectDevices:
        navigator.pushNamed(AppRoutes.deviceSync);
      case AppTool.savedPhrases:
        navigator.pushNamed(AppRoutes.savedPhrases);
      case AppTool.learn:
        navigator.pushNamed(AppRoutes.learningModule);
      case AppTool.customSigns:
        navigator.pushNamed(AppRoutes.customSigns);
    }
  }
}
