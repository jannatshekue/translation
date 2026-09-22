import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:translation/core/services/database_service.dart';

void main() {
  // The real sqflite plugin talks to platform code that doesn't exist in
  // this test environment; swap in the FFI backend (real SQLite, no
  // platform channel) so DatabaseService's own code runs unmodified.
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // DatabaseService is a singleton pointed at a fixed file path, so each
  // test must close AND delete it — otherwise the next test reopens the
  // same on-disk database and sees the previous test's rows.
  tearDown(() async {
    await DatabaseService.instance.close();
    final path = p.join(await databaseFactory.getDatabasesPath(), 'translation.db');
    await databaseFactory.deleteDatabase(path);
  });

  group('custom signs', () {
    test('insert, list, and delete a custom sign', () async {
      final id = await DatabaseService.instance.insertCustomSign(
        label: 'Hello',
        landmarkSequenceJson: '[[{"type":"wrist","x":0,"y":0,"z":0,"visibility":1}]]',
      );

      final signs = await DatabaseService.instance.getCustomSigns();
      expect(signs, hasLength(1));
      expect(signs.single.id, id);
      expect(signs.single.label, 'Hello');

      await DatabaseService.instance.deleteCustomSign(id);
      expect(await DatabaseService.instance.getCustomSigns(), isEmpty);
    });

    test('lists most recently created sign first', () async {
      await DatabaseService.instance.insertCustomSign(label: 'First', landmarkSequenceJson: '[]');
      await Future.delayed(const Duration(milliseconds: 2));
      await DatabaseService.instance.insertCustomSign(label: 'Second', landmarkSequenceJson: '[]');

      final signs = await DatabaseService.instance.getCustomSigns();
      expect(signs.map((s) => s.label).toList(), ['Second', 'First']);
    });
  });

  group('saved phrases', () {
    test('insert, list, and delete a saved phrase', () async {
      final id = await DatabaseService.instance.insertSavedPhrase('I need help');

      final phrases = await DatabaseService.instance.getSavedPhrases();
      expect(phrases, hasLength(1));
      expect(phrases.single.id, id);
      expect(phrases.single.text, 'I need help');

      await DatabaseService.instance.deleteSavedPhrase(id);
      expect(await DatabaseService.instance.getSavedPhrases(), isEmpty);
    });
  });
}
