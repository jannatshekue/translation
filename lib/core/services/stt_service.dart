import 'package:speech_to_text/speech_to_text.dart';

/// Wraps the on-device (offline) speech recognizer. This is the default path
/// per the offline-first requirement; the online Google Speech-to-Text API
/// path is a separate, later addition for when connectivity is available and
/// higher accuracy is wanted — it must never be required for this to work.
class SttService {
  SttService._internal();

  static final SttService instance = SttService._internal();

  final SpeechToText _speech = SpeechToText();
  bool _isInitialized = false;
  List<LocaleName>? _cachedLocales;

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    _isInitialized = await _speech.initialize();
    return _isInitialized;
  }

  /// Locales this device's speech recognizer actually supports. Cached
  /// after the first call — this list doesn't change during a session.
  Future<List<LocaleName>> getAvailableLocales() async {
    final cached = _cachedLocales;
    if (cached != null) return cached;
    final available = await initialize();
    if (!available) return const [];
    final locales = await _speech.locales();
    _cachedLocales = locales;
    return locales;
  }

  /// Starts listening. Pass [localeId] (from [getAvailableLocales]) to
  /// recognize a specific language; omit it to use the system default.
  /// [onResult] receives the recognized text so far and whether the
  /// recognizer has determined the utterance is complete (useful for
  /// turn-based flows that should act once the speaker finishes).
  Future<void> startListening(
    void Function(String recognizedText, bool isFinal) onResult, {
    String? localeId,
  }) async {
    final available = await initialize();
    if (!available) return;
    await _speech.listen(
      onResult: (result) => onResult(result.recognizedWords, result.finalResult),
      listenOptions: SpeechListenOptions(localeId: localeId),
    );
  }

  Future<void> stopListening() async {
    await _speech.stop();
  }

  bool get isListening => _speech.isListening;
}
