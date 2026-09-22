import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  TtsService._internal();

  static final TtsService instance = TtsService._internal();

  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;
  List<String>? _cachedLanguages;

  Future<void> initialize() async {
    if (_isInitialized) return;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _isInitialized = true;
  }

  /// Language tags this device's TTS engine can actually speak (e.g. "es-ES").
  /// Cached after the first call — this list doesn't change during a session.
  Future<List<String>> getAvailableLanguages() async {
    final cached = _cachedLanguages;
    if (cached != null) return cached;
    await initialize();
    final languages = await _tts.getLanguages;
    final result = (languages as List<dynamic>).cast<String>();
    _cachedLanguages = result;
    return result;
  }

  /// Speaks [text]. Pass [language] to switch the TTS engine's output
  /// language first; omit it to keep whatever language was set last.
  Future<void> speak(String text, {String? language}) async {
    await initialize();
    if (language != null) {
      await _tts.setLanguage(language);
    }
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}
