import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../../core/services/settings_service.dart';
import '../../../../core/services/stt_service.dart';
import '../../../../core/services/tts_service.dart';
import '../../../../core/utils/permission_primer.dart';
import '../../../../routes/app_routes.dart';
import '../../../../shared/widgets/app_background.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../shared/widgets/section_card.dart';
import 'conversation_screen.dart';

/// Single-user speech-to-text and text-to-speech, each with its own language
/// picker — for transcribing your own speech or reading text aloud. Both
/// directions work fully offline via on-device recognition and synthesis.
/// For translating between two people speaking different languages, see
/// [ConversationScreen].
class VoiceTranslationScreen extends StatefulWidget {
  const VoiceTranslationScreen({super.key});

  @override
  State<VoiceTranslationScreen> createState() => _VoiceTranslationScreenState();
}

class _VoiceTranslationScreenState extends State<VoiceTranslationScreen> {
  final TextEditingController _textController = TextEditingController();
  bool _isListening = false;
  String _recognizedText = '';
  String _status = '';

  List<LocaleName> _sttLocales = [];
  String? _selectedSttLocaleId;

  List<String> _ttsLanguages = [];
  String _selectedTtsLanguage = 'en-US';

  @override
  void initState() {
    super.initState();
    _loadTtsLanguages();
    _loadSttLocales();
  }

  Future<void> _loadTtsLanguages() async {
    final languages = await TtsService.instance.getAvailableLanguages();
    if (!mounted) return;
    setState(() {
      _ttsLanguages = languages;
      if (languages.isNotEmpty && !languages.contains(_selectedTtsLanguage)) {
        _selectedTtsLanguage = languages.first;
      }
    });
  }

  Future<void> _loadSttLocales() async {
    final locales = await SttService.instance.getAvailableLocales();
    if (mounted) setState(() => _sttLocales = locales);
  }

  Future<void> _toggleListening() async {
    SettingsService.instance.hapticTap();
    if (_isListening) {
      await SttService.instance.stopListening();
      setState(() => _isListening = false);
      return;
    }

    if (!mounted) return;
    final micGranted = await PermissionPrimer.requestWithRationale(
      context,
      permission: Permission.microphone,
      title: 'Microphone access',
      message: 'Voice Translation needs your microphone to hear and transcribe your speech.',
    );
    if (!micGranted) {
      setState(() => _status = 'Microphone permission denied.');
      return;
    }
    await Permission.speech.request();

    final available = await SttService.instance.initialize();
    if (!available) {
      setState(() => _status = 'Speech recognition unavailable on this device.');
      return;
    }
    if (_sttLocales.isEmpty) {
      await _loadSttLocales();
    }

    setState(() {
      _isListening = true;
      _status = '';
    });
    await SttService.instance.startListening(
      (text, isFinal) => setState(() => _recognizedText = text),
      localeId: _selectedSttLocaleId,
    );
  }

  Future<void> _speakTypedText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    SettingsService.instance.hapticTap();
    await TtsService.instance.speak(text, language: _selectedTtsLanguage);
  }

  @override
  void dispose() {
    SttService.instance.stopListening();
    _textController.dispose();
    super.dispose();
  }

  Widget _sectionHeader(BuildContext context, ColorScheme colorScheme, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurfaceVariant,
          ),
    );
  }

  Widget _buildSpeechToTextSection(BuildContext context, ColorScheme colorScheme) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_sttLocales.isNotEmpty)
            DropdownButtonFormField<String?>(
              initialValue: _selectedSttLocaleId,
              decoration: const InputDecoration(
                labelText: 'Listen in',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('System default')),
                for (final locale in _sttLocales)
                  DropdownMenuItem(value: locale.localeId, child: Text(locale.name)),
              ],
              onChanged: (value) => setState(() => _selectedSttLocaleId = value),
            ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            constraints: const BoxConstraints(minHeight: 90),
            child: Text(
              _recognizedText.isEmpty ? 'Tap the mic and start speaking…' : _recognizedText,
            ),
          ),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_status, style: TextStyle(color: colorScheme.error)),
          ],
          const SizedBox(height: 16),
          Center(
            child: PressableScale(
              borderRadius: BorderRadius.circular(36),
              onTap: _toggleListening,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: _isListening
                        ? [Colors.red, Colors.redAccent]
                        : [colorScheme.primary, colorScheme.tertiary],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (_isListening ? Colors.red : colorScheme.primary)
                          .withValues(alpha: 0.35),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(
                  _isListening ? Icons.mic : Icons.mic_none,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextToSpeechSection(BuildContext context, ColorScheme colorScheme) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_ttsLanguages.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _selectedTtsLanguage,
              decoration: const InputDecoration(
                labelText: 'Speak in',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final language in _ttsLanguages)
                  DropdownMenuItem(value: language, child: Text(language)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _selectedTtsLanguage = value);
              },
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _textController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Type text to speak aloud',
            ),
            minLines: 2,
            maxLines: 4,
          ),
          const SizedBox(height: 12),
          PressableScale(
            borderRadius: BorderRadius.circular(12),
            onTap: _speakTypedText,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.volume_up, color: colorScheme.onPrimary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Speak',
                    style: TextStyle(color: colorScheme.onPrimary, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // speechImpaired users primarily communicate via typed text spoken
    // aloud, since they may not be able to speak into the mic; everyone
    // else reads others' speech as text first. Both directions always stay
    // available regardless of order.
    final ttsFirst = SettingsService.instance.userProfile == UserProfile.speechImpaired;

    final speechToText = [
      _sectionHeader(context, colorScheme, 'Speech to text'),
      const SizedBox(height: 8),
      _buildSpeechToTextSection(context, colorScheme),
    ];
    final textToSpeech = [
      _sectionHeader(context, colorScheme, 'Text to speech'),
      const SizedBox(height: 8),
      _buildTextToSpeechSection(context, colorScheme),
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Voice Translation'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AppBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PressableScale(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {
                    SettingsService.instance.hapticTap();
                    Navigator.of(context).pushNamed(AppRoutes.conversationMode);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [colorScheme.secondary, colorScheme.tertiary],
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.forum, color: Colors.white),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Conversation Mode — translate between two people',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ...(ttsFirst ? textToSpeech : speechToText),
                const SizedBox(height: 24),
                ...(ttsFirst ? speechToText : textToSpeech),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
