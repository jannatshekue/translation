import 'package:flutter/material.dart';

import '../features/custom_signs/presentation/screens/custom_signs_screen.dart';
import '../features/device_sync/presentation/screens/device_sync_screen.dart';
import '../features/emergency_mode/presentation/screens/emergency_mode_screen.dart';
import '../features/home/presentation/screens/home_screen.dart';
import '../features/learning_module/presentation/screens/learning_module_screen.dart';
import '../features/onboarding/presentation/screens/profile_selection_screen.dart';
import '../features/saved_phrases/presentation/screens/saved_phrases_screen.dart';
import '../features/settings/presentation/screens/settings_screen.dart';
import '../features/sign_recognition/presentation/screens/sign_recognition_screen.dart';
import '../features/splash/presentation/screens/splash_screen.dart';
import '../features/voice_translation/presentation/screens/conversation_screen.dart';
import '../features/voice_translation/presentation/screens/voice_translation_screen.dart';

class AppRoutes {
  AppRoutes._();

  static const String splash = '/splash';
  static const String profileSelection = '/profile-selection';
  static const String home = '/';
  static const String signRecognition = '/sign-recognition';
  static const String voiceTranslation = '/voice-translation';
  static const String conversationMode = '/conversation-mode';
  static const String deviceSync = '/device-sync';
  static const String emergencyMode = '/emergency-mode';
  static const String customSigns = '/custom-signs';
  static const String learningModule = '/learning-module';
  static const String savedPhrases = '/saved-phrases';
  static const String settings = '/settings';

  static Map<String, WidgetBuilder> get routes => {
        splash: (context) => const SplashScreen(),
        profileSelection: (context) => const ProfileSelectionScreen(),
        home: (context) => const HomeScreen(),
        signRecognition: (context) => const SignRecognitionScreen(),
        voiceTranslation: (context) => const VoiceTranslationScreen(),
        conversationMode: (context) => const ConversationScreen(),
        deviceSync: (context) => const DeviceSyncScreen(),
        emergencyMode: (context) => const EmergencyModeScreen(),
        customSigns: (context) => const CustomSignsScreen(),
        learningModule: (context) => const LearningModuleScreen(),
        savedPhrases: (context) => const SavedPhrasesScreen(),
        settings: (context) => const SettingsScreen(),
      };
}
