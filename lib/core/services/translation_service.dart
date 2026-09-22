import 'package:google_mlkit_translation/google_mlkit_translation.dart';

/// On-device translation between two languages via Google ML Kit. Runs
/// fully offline once each language's model is downloaded (a one-time,
/// free download — no API key or billing account, unlike cloud translation
/// APIs), matching the app's offline-first requirement.
class TranslationService {
  TranslationService._internal();

  static final TranslationService instance = TranslationService._internal();

  final OnDeviceTranslatorModelManager _modelManager = OnDeviceTranslatorModelManager();
  final Map<String, OnDeviceTranslator> _translators = {};

  /// Maps a locale/language tag (e.g. "es-ES", "es_ES", "es") to the ML Kit
  /// language it represents, using just the language subtag. Returns null
  /// if ML Kit doesn't support that language.
  static TranslateLanguage? languageFor(String tag) {
    final code = tag.split(RegExp('[-_]')).first.toLowerCase();
    return BCP47Code.fromRawValue(code);
  }

  Future<void> _ensureModelDownloaded(TranslateLanguage language) async {
    final downloaded = await _modelManager.isModelDownloaded(language.bcpCode);
    if (!downloaded) {
      await _modelManager.downloadModel(language.bcpCode);
    }
  }

  Future<String> translate(
    String text, {
    required TranslateLanguage from,
    required TranslateLanguage to,
  }) async {
    if (from == to) return text;
    await _ensureModelDownloaded(from);
    await _ensureModelDownloaded(to);

    final key = '${from.bcpCode}->${to.bcpCode}';
    final translator = _translators.putIfAbsent(
      key,
      () => OnDeviceTranslator(sourceLanguage: from, targetLanguage: to),
    );
    return translator.translateText(text);
  }

  Future<void> dispose() async {
    for (final translator in _translators.values) {
      await translator.close();
    }
    _translators.clear();
  }
}
