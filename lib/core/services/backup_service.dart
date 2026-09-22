import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'database_service.dart';

class ImportResult {
  final bool imported;
  final int signsCount;
  final int phrasesCount;

  const ImportResult({
    required this.imported,
    required this.signsCount,
    required this.phrasesCount,
  });
}

/// Local backup/restore for custom signs and saved phrases — the only user
/// data that isn't otherwise recoverable, since there's no cloud backend.
/// Export hands a JSON file to the OS share sheet (save to Drive, email,
/// files app, etc.); import reads one back in.
class BackupService {
  BackupService._internal();

  static final BackupService instance = BackupService._internal();

  Future<void> exportData() async {
    final signs = await DatabaseService.instance.getCustomSigns();
    final phrases = await DatabaseService.instance.getSavedPhrases();

    final data = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'customSigns': signs
          .map((s) => {
                'label': s.label,
                'landmarkSequence': s.landmarkSequenceJson,
                'createdAt': s.createdAt.millisecondsSinceEpoch,
              })
          .toList(),
      'savedPhrases': phrases
          .map((p) => {
                'text': p.text,
                'createdAt': p.createdAt.millisecondsSinceEpoch,
              })
          .toList(),
    };

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/translation_backup.json');
    await file.writeAsString(jsonEncode(data));

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'Sign & Voice Translator backup',
      ),
    );
  }

  Future<ImportResult> importData() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked == null) {
      return const ImportResult(imported: false, signsCount: 0, phrasesCount: 0);
    }

    final bytes = await picked.readAsBytes();
    final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

    final signs = (data['customSigns'] as List<dynamic>?) ?? const [];
    for (final entry in signs) {
      final map = entry as Map<String, dynamic>;
      await DatabaseService.instance.insertCustomSign(
        label: map['label'] as String,
        landmarkSequenceJson: map['landmarkSequence'] as String,
      );
    }

    final phrases = (data['savedPhrases'] as List<dynamic>?) ?? const [];
    for (final entry in phrases) {
      final map = entry as Map<String, dynamic>;
      await DatabaseService.instance.insertSavedPhrase(map['text'] as String);
    }

    return ImportResult(
      imported: true,
      signsCount: signs.length,
      phrasesCount: phrases.length,
    );
  }
}
