import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:translation/core/services/database_service.dart';
import 'package:translation/core/services/settings_service.dart';
import 'package:translation/core/services/starter_phrases.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Test files run in parallel processes; a private folder keeps this
    // file's database from colliding with the other database tests'.
    await databaseFactory.setDatabasesPath(Directory.systemTemp.createTempSync('starter_phrases_').path);
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  tearDown(() async {
    await DatabaseService.instance.close();
    final path = p.join(await databaseFactory.getDatabasesPath(), 'translation.db');
    await databaseFactory.deleteDatabase(path);
  });

  Future<List<String>> saved() async =>
      [for (final phrase in await DatabaseService.instance.getSavedPhrases()) phrase.text];

  test('first launch saves the everyday phrases, most important first', () async {
    await StarterPhrases.seedIfNeeded();

    final phrases = await saved();
    expect(phrases, StarterPhrases.general);
    expect(phrases.first, 'Please help me.');
    expect(phrases, containsAll(['Pardon?', 'Excuse me.', "I'm sorry.", 'Thank you.']));
  });

  test('seeding happens once: a deleted phrase does not come back', () async {
    await StarterPhrases.seedIfNeeded();
    final all = await DatabaseService.instance.getSavedPhrases();
    await DatabaseService.instance.deleteSavedPhrase(all.first.id);

    await StarterPhrases.seedIfNeeded();

    expect(await saved(), hasLength(StarterPhrases.general.length - 1));
  });

  test("someone's own phrases are kept and the essentials are added beside them", () async {
    await DatabaseService.instance.insertSavedPhrase('My own phrase');

    await StarterPhrases.seedIfNeeded();

    final phrases = await saved();
    expect(phrases, contains('My own phrase'));
    expect(phrases, containsAll(StarterPhrases.general));
    expect(phrases, hasLength(StarterPhrases.general.length + 1));
  });

  test('an essential they already have is not duplicated, only the missing ones are added', () async {
    // The small set an earlier version saved: no full stops.
    for (final old in ['Yes', 'No', 'Thank you']) {
      await DatabaseService.instance.insertSavedPhrase(old);
    }

    await StarterPhrases.seedIfNeeded();

    final phrases = await saved();
    expect(phrases.where((t) => t.toLowerCase().startsWith('yes')), hasLength(1));
    expect(phrases.where((t) => t.toLowerCase().startsWith('thank you')), hasLength(1));
    expect(phrases, containsAll(['Pardon?', 'Excuse me.', "I'm sorry."]));
  });

  test('an essential they already have is moved into its place in the list', () async {
    await DatabaseService.instance.insertSavedPhrase('Please help me'); // old, no full stop
    await DatabaseService.instance.insertSavedPhrase('Zebra phrase');   // newer, theirs

    await StarterPhrases.seedIfNeeded();

    final phrases = await saved();
    expect(phrases.first, 'Please help me', reason: 'the most important phrase leads');
    expect(phrases.where((t) => t.toLowerCase().startsWith('please help me')), hasLength(1));
    expect(phrases, contains('Zebra phrase'));
  });

  test('profile extras are added once per profile', () async {
    await StarterPhrases.seedIfNeeded();
    await StarterPhrases.seedForProfile(UserProfile.speechImpaired);
    await StarterPhrases.seedForProfile(UserProfile.speechImpaired);

    final phrases = await saved();
    for (final extra in StarterPhrases.forSpeech) {
      expect(phrases.where((t) => t == extra), hasLength(1));
    }
    expect(phrases.first, StarterPhrases.forSpeech.first, reason: 'profile extras are listed first');
  });

  test('the hearing-and-speaking profile adds no extras', () async {
    await StarterPhrases.seedIfNeeded();
    await StarterPhrases.seedForProfile(UserProfile.normal);

    expect(await saved(), hasLength(StarterPhrases.general.length));
  });
}
