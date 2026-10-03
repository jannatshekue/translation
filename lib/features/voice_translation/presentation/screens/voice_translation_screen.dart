import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../../core/profile/app_tools.dart';
import '../../../../core/profile/profile_experience.dart';
import '../../../../core/services/database_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/services/stt_service.dart';
import '../../../../core/services/tts_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_permissions.dart';
import '../../../../core/utils/priority_languages.dart';
import '../../../../models/saved_phrase.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../shared/widgets/section_header.dart';

/// Speech ↔ text for one person, two clearly separated halves:
///  * Listen — live captions of what's being said (speech to text).
///  * Speak — type something and the phone says it aloud (text to speech).
///
/// Which half opens first, and whether the mic or the keyboard starts
/// straight away, is decided by the person's profile (see
/// [ProfileExperience]). Both halves work fully offline.
class VoiceTranslationScreen extends StatefulWidget {
  const VoiceTranslationScreen({super.key});

  @override
  State<VoiceTranslationScreen> createState() => _VoiceTranslationScreenState();
}

class _VoiceTranslationScreenState extends State<VoiceTranslationScreen> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocus = FocusNode();

  late VoiceMode _mode;
  bool _argsRead = false;

  bool _isListening = false;
  String _recognizedText = '';
  String _status = '';

  List<LocaleName> _sttLocales = [];
  String? _selectedSttLocaleId;

  List<String> _ttsLanguages = [];
  String _selectedTtsLanguage = 'en-US';

  List<SavedPhrase> _phrases = [];

  @override
  void initState() {
    super.initState();
    _mode = ProfileExperience.of(SettingsService.instance.userProfile).voiceMode;
    _loadTtsLanguages();
    _loadSttLocales();
    _loadPhrases();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsRead) return;
    _argsRead = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is VoiceScreenArgs) {
      _mode = args.mode;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (args.autoListen) _toggleListening();
        if (args.autoFocusTyping) {
          _textFocus.requestFocus();
          // Focus alone doesn't always raise the keyboard on a screen that
          // has just opened; ask for it explicitly.
          SystemChannels.textInput.invokeMethod<void>('TextInput.show');
        }
      });
    }
  }

  Future<void> _loadTtsLanguages() async {
    final languages = sortByPriority(await TtsService.instance.getAvailableLanguages());
    if (!mounted) return;
    setState(() {
      _ttsLanguages = languages;
      if (languages.isNotEmpty && !languages.contains(_selectedTtsLanguage)) {
        _selectedTtsLanguage = languages.first;
      }
    });
  }

  Future<void> _loadSttLocales() async {
    final locales = sortByPriorityWith(
      await SttService.instance.getAvailableLocalesIfPermitted(),
      (l) => l.localeId,
    );
    if (mounted) setState(() => _sttLocales = locales);
  }

  Future<void> _loadPhrases() async {
    try {
      final phrases = await DatabaseService.instance.getSavedPhrases();
      if (mounted) setState(() => _phrases = phrases);
    } catch (_) {
      // Quick phrases are optional.
    }
  }

  Widget? _missingLanguagesHint(ColorScheme colorScheme, List<String> availableTags) {
    if (availableTags.isEmpty) return null;
    final missing = missingPriorityLanguages(availableTags);
    if (missing.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'Not available on this device\'s speech engine: '
        '${missing.map((m) => m.displayName).join(', ')}.',
        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
      ),
    );
  }

  Future<void> _toggleListening() async {
    SettingsService.instance.hapticTap();
    if (_isListening) {
      await SttService.instance.stopListening();
      setState(() => _isListening = false);
      return;
    }

    if (!mounted) return;
    final micGranted = await AppPermissions.ensure(context, Permission.microphone, announceDenial: false);
    if (!micGranted) {
      if (mounted) setState(() => _status = AppPermissions.neededMessage(Permission.microphone));
      return;
    }
    await Permission.speech.request();

    final available = await SttService.instance.initialize();
    if (!available) {
      if (mounted) setState(() => _status = 'Speech recognition is unavailable on this device.');
      return;
    }
    if (_sttLocales.isEmpty) {
      await _loadSttLocales();
    }

    if (!mounted) return;
    setState(() {
      _isListening = true;
      _status = '';
    });
    await SttService.instance.startListening(
      (text, isFinal) {
        if (!mounted) return;
        setState(() => _recognizedText = text);
      },
      localeId: _selectedSttLocaleId,
    );
  }

  Future<void> _speakTypedText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    SettingsService.instance.hapticTap();
    await TtsService.instance.speak(text, language: _selectedTtsLanguage);
  }

  Future<void> _savePhrase() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    SettingsService.instance.hapticTap();
    await DatabaseService.instance.insertSavedPhrase(text);
    await _loadPhrases();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved to your phrases')));
    }
  }

  @override
  void dispose() {
    SttService.instance.stopListening();
    _textController.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  Widget _buildListen(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isHearing = SettingsService.instance.userProfile == UserProfile.hearingImpaired;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_sttLocales.isNotEmpty) ...[
          DropdownButtonFormField<String?>(
            initialValue: _selectedSttLocaleId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Language being spoken'),
            items: [
              const DropdownMenuItem(value: null, child: Text('System default')),
              for (final locale in _sttLocales)
                DropdownMenuItem(value: locale.localeId, child: Text(locale.name)),
            ],
            onChanged: (value) => setState(() => _selectedSttLocaleId = value),
          ),
          _missingLanguagesHint(scheme, _sttLocales.map((l) => l.localeId).toList()) ??
              const SizedBox.shrink(),
          const SizedBox(height: 16),
        ],
        // The caption surface: large, high-contrast, easy to read at a glance.
        Container(
          constraints: const BoxConstraints(minHeight: 220),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(
              color: _isListening ? scheme.primary : scheme.outlineVariant,
              width: _isListening ? 2 : 1,
            ),
          ),
          child: _recognizedText.isEmpty
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    Icon(
                      _isListening ? Icons.hearing : Icons.closed_caption_outlined,
                      size: 40,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isListening ? 'Listening… start speaking' : 'Captions will appear here',
                      style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 40),
                  ],
                )
              : Text(
                  _recognizedText,
                  style: (isHearing ? theme.textTheme.headlineSmall : theme.textTheme.titleLarge)
                      ?.copyWith(height: 1.35, fontWeight: FontWeight.w600),
                ),
        ),
        if (_status.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(_status, style: TextStyle(color: scheme.error)),
        ],
        const SizedBox(height: 24),
        Center(
          child: Column(
            children: [
              PressableScale(
                borderRadius: BorderRadius.circular(40),
                onTap: _toggleListening,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isListening ? AppTheme.emergency : scheme.primary,
                    boxShadow: [
                      BoxShadow(
                        color: (_isListening ? AppTheme.emergency : scheme.primary).withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isListening ? Icons.stop_rounded : Icons.mic,
                    color: scheme.onPrimary,
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _isListening ? 'Tap to stop' : 'Tap to start captions',
                style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        if (_recognizedText.isNotEmpty && !_isListening) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _recognizedText = ''),
              icon: const Icon(Icons.clear),
              label: const Text('Clear captions'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSpeak(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_ttsLanguages.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            initialValue: _selectedTtsLanguage,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Speak in'),
            items: [
              for (final language in _ttsLanguages)
                DropdownMenuItem(value: language, child: Text(language)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _selectedTtsLanguage = value);
            },
          ),
          _missingLanguagesHint(scheme, _ttsLanguages) ?? const SizedBox.shrink(),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _textController,
          focusNode: _textFocus,
          minLines: 4,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          style: theme.textTheme.titleMedium,
          decoration: const InputDecoration(hintText: 'Type what you want to say…'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _textController.text.trim().isEmpty ? null : _speakTypedText,
                icon: const Icon(Icons.volume_up),
                label: const Text('Speak'),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: _textController.text.trim().isEmpty ? null : _savePhrase,
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('Save'),
            ),
          ],
        ),
        if (_phrases.isNotEmpty) ...[
          const SizedBox(height: 28),
          const SectionHeader('Tap a phrase to say it'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final phrase in _phrases)
                ActionChip(
                  avatar: Icon(Icons.volume_up_outlined, size: 18, color: scheme.primary),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Text(phrase.text, overflow: TextOverflow.ellipsis),
                  ),
                  onPressed: () {
                    SettingsService.instance.hapticImpact();
                    TtsService.instance.speak(phrase.text, language: _selectedTtsLanguage);
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Speech & text')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppTheme.screenPadding, 4, AppTheme.screenPadding, 28),
          children: [
            SegmentedButton<VoiceMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: VoiceMode.listen,
                  icon: Icon(Icons.closed_caption_outlined),
                  label: Text('Listen'),
                ),
                ButtonSegment(
                  value: VoiceMode.speak,
                  icon: Icon(Icons.record_voice_over_outlined),
                  label: Text('Speak'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) {
                SettingsService.instance.hapticTap();
                setState(() => _mode = selection.first);
              },
            ),
            const SizedBox(height: 20),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: KeyedSubtree(
                key: ValueKey(_mode),
                child: _mode == VoiceMode.listen ? _buildListen(context) : _buildSpeak(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
