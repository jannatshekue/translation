import 'package:flutter/material.dart';

import '../../../../core/services/database_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/services/tts_service.dart';
import '../../../../models/saved_phrase.dart';
import '../../../../shared/widgets/app_background.dart';
import '../../../../shared/widgets/pressable_scale.dart';

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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Saved Phrases'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Material(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(28),
                  elevation: 2,
                  shadowColor: Colors.black.withValues(alpha: 0.15),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _textController,
                            decoration: const InputDecoration(
                              hintText: 'Add a quick-access phrase',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            ),
                            onSubmitted: (_) => _addPhrase(),
                          ),
                        ),
                        PressableScale(
                          borderRadius: BorderRadius.circular(24),
                          onTap: _addPhrase,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.add, color: colorScheme.onPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _phrases.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bookmark_border, size: 48, color: colorScheme.onSurfaceVariant),
                            const SizedBox(height: 12),
                            Text(
                              'No saved phrases yet',
                              style: TextStyle(color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: _phrases.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final phrase = _phrases[index];
                          return TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: 1),
                            duration: Duration(milliseconds: 260 + index * 40),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, child) => Opacity(
                              opacity: value,
                              child: Transform.translate(
                                offset: Offset((1 - value) * 16, 0),
                                child: child,
                              ),
                            ),
                            child: Material(
                              color: colorScheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              elevation: 1,
                              shadowColor: Colors.black.withValues(alpha: 0.1),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        phrase.text,
                                        style: Theme.of(context).textTheme.bodyLarge,
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.volume_up, color: colorScheme.primary),
                                      onPressed: () {
                                        SettingsService.instance.hapticTap();
                                        TtsService.instance.speak(phrase.text);
                                      },
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete_outline, color: colorScheme.error),
                                      onPressed: () => _deletePhrase(phrase.id),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
