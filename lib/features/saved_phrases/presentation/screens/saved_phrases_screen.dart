import 'package:flutter/material.dart';

import '../../../../core/services/database_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/services/tts_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/saved_phrase.dart';
import '../../../../shared/widgets/section_card.dart';

/// Phrases the person says often. Tapping a row speaks it immediately.
class SavedPhrasesScreen extends StatefulWidget {
  const SavedPhrasesScreen({super.key});

  @override
  State<SavedPhrasesScreen> createState() => _SavedPhrasesScreenState();
}

class _SavedPhrasesScreenState extends State<SavedPhrasesScreen> {
  final TextEditingController _textController = TextEditingController();
  List<SavedPhrase> _phrases = [];

  @override
  void initState() {
    super.initState();
    _loadPhrases();
  }

  Future<void> _loadPhrases() async {
    final phrases = await DatabaseService.instance.getSavedPhrases();
    if (mounted) setState(() => _phrases = phrases);
  }

  Future<void> _addPhrase() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    SettingsService.instance.hapticTap();
    await DatabaseService.instance.insertSavedPhrase(text);
    _textController.clear();
    await _loadPhrases();
  }

  Future<void> _deletePhrase(int id) async {
    SettingsService.instance.hapticTap();
    await DatabaseService.instance.deleteSavedPhrase(id);
    await _loadPhrases();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Saved phrases')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppTheme.screenPadding, 4, AppTheme.screenPadding, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(hintText: 'Add a phrase you say often'),
                      onSubmitted: (_) => _addPhrase(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    tooltip: 'Add phrase',
                    onPressed: _addPhrase,
                    style: IconButton.styleFrom(minimumSize: const Size(54, 54)),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _phrases.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bookmark_border, size: 56, color: scheme.outline),
                            const SizedBox(height: 14),
                            Text('No saved phrases yet', style: theme.textTheme.titleMedium),
                            const SizedBox(height: 6),
                            Text(
                              'Add things you say often — "I need help", "Thank you" — and say them in one tap.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(AppTheme.screenPadding, 4, AppTheme.screenPadding, 24),
                      itemCount: _phrases.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final phrase = _phrases[index];
                        return SectionCard(
                          padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                          onTap: () {
                            SettingsService.instance.hapticImpact();
                            TtsService.instance.speak(phrase.text);
                          },
                          child: Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Text(phrase.text, style: theme.textTheme.bodyLarge),
                                ),
                              ),
                              Icon(Icons.volume_up_outlined, color: scheme.primary),
                              IconButton(
                                tooltip: 'Delete',
                                icon: Icon(Icons.delete_outline, color: scheme.onSurfaceVariant),
                                onPressed: () => _deletePhrase(phrase.id),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
