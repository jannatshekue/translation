import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:translation/core/services/translation_service.dart';

void main() {
  group('TranslationService.languageFor', () {
    test('maps a full locale tag to its ML Kit language', () {
      expect(TranslationService.languageFor('es-ES'), TranslateLanguage.spanish);
      expect(TranslationService.languageFor('en-US'), TranslateLanguage.english);
      expect(TranslationService.languageFor('fr-FR'), TranslateLanguage.french);
    });

    test('maps a bare language subtag with no region', () {
      expect(TranslationService.languageFor('de'), TranslateLanguage.german);
    });

    test('is case-insensitive and handles underscore separators', () {
      expect(TranslationService.languageFor('PT_BR'), TranslateLanguage.portuguese);
    });

    test('returns null for a language ML Kit does not support', () {
      expect(TranslationService.languageFor('zz-ZZ'), isNull);
    });
  });
}
