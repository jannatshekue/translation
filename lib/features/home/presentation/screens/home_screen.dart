import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../../core/profile/app_tools.dart';
import '../../../../core/profile/profile_experience.dart';
import '../../../../core/services/app_events.dart';
import '../../../../core/services/database_service.dart';
import '../../../../core/services/learning_progress_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/services/starter_phrases.dart';
import '../../../../core/services/tts_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/saved_phrase.dart';
import '../../../../routes/app_routes.dart';
import '../../../../shared/widgets/action_tile.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../shared/widgets/profile_sheet.dart';
import '../../../../shared/widgets/section_card.dart';
import '../../../../shared/widgets/section_header.dart';
import '../../../shell/presentation/screens/main_shell.dart';

/// Home: the single most useful thing to do right now (a hero action chosen
/// by the person's profile), a one-tap route to the emergency alert, and
/// shortcuts to the rest — ordered for how this person communicates.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<SavedPhrase> _phrases = [];
  int _lessonsDone = 0;
  int _lessonsTotal = 0;

  @override
  void initState() {
    super.initState();
    SettingsService.instance.addListener(_onSettingsChanged);
    AppEvents.phrasesChanged.addListener(_loadSnapshot);
    AppEvents.progressChanged.addListener(_loadSnapshot);
    // Everyone gets the everyday phrases once; then load whatever is saved.
    StarterPhrases.seedIfNeeded().whenComplete(_loadSnapshot);
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_onSettingsChanged);
    AppEvents.phrasesChanged.removeListener(_loadSnapshot);
    AppEvents.progressChanged.removeListener(_loadSnapshot);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
    _loadSnapshot();
  }

  Future<void> _loadSnapshot() async {
    try {
      final done = await LearningProgressService.instance.getCompletedLessonIds();
      final raw = await rootBundle.loadString('assets/lessons/lessons.json');
      final total = (jsonDecode(raw) as List<dynamic>).length;
      final phrases =
          _showPhrases ? await DatabaseService.instance.getSavedPhrases() : <SavedPhrase>[];
      if (!mounted) return;
      setState(() {
        _lessonsDone = done.length;
        _lessonsTotal = total;
        _phrases = phrases;
      });
    } catch (_) {
      // Shortcuts simply stay empty if storage isn't available.
    }
  }

  /// Quick phrases show by default where they matter most (people who
  /// communicate by typing or text); anyone else turns them on by choice.
  bool get _showPhrases {
    final choice = SettingsService.instance.quickPhrasesOnHome;
    if (choice != null) return choice;
    return ProfileExperience.of(SettingsService.instance.userProfile).showQuickPhrases;
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _switchProfile() async {
    await showProfileSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final experience = ProfileExperience.of(SettingsService.instance.userProfile);

    final listedTools = experience.toolOrder.take(5).toList();

    final sections = <Widget>[
      _Header(
        greeting: _greeting,
        profileLabel: experience.label,
        onProfileTap: _switchProfile,
        onSettingsTap: () {
          SettingsService.instance.hapticTap();
          Navigator.of(context).pushNamed(AppRoutes.settings);
        },
      ),
      const SizedBox(height: 20),
      _HeroCard(experience: experience),
      const SizedBox(height: 14),
      _EmergencyStrip(onTap: () => ShellNavigation.goTo(ShellNavigation.emergency)),
      if (_showPhrases) ...[
        const SizedBox(height: 24),
        SectionHeader(
          'Quick phrases',
          actionLabel: 'Manage',
          onAction: () => Navigator.of(context).pushNamed(AppRoutes.savedPhrases),
        ),
        if (_phrases.isNotEmpty)
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _phrases.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) => _PhraseChip(text: _phrases[index].text),
            ),
          )
        else
          SectionCard(
            onTap: () => Navigator.of(context).pushNamed(AppRoutes.savedPhrases),
            child: Row(
              children: [
                Icon(Icons.bookmark_add_outlined, color: scheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'No quick phrases yet. Tap to add the ones you say most.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
      ],
      const SizedBox(height: 24),
      SectionHeader(
        'Your tools',
        actionLabel: 'See all',
        onAction: () => ShellNavigation.goTo(ShellNavigation.communicate),
      ),
      ActionGroup(
        children: [
          for (final tool in listedTools)
            ActionTile(
              icon: tool.icon,
              title: tool.title,
              subtitle: tool.subtitle,
              color: tool.color,
              recommended: experience.recommended.contains(tool),
              onTap: () => tool.open(context),
            ),
        ],
      ),
      if (!_showPhrases) ...[
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              SettingsService.instance.hapticTap();
              SettingsService.instance.setQuickPhrasesOnHome(true);
            },
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: const Text('Show quick phrases on Home'),
          ),
        ),
      ],
      if (_lessonsTotal > 0) ...[
        const SizedBox(height: 24),
        const SectionHeader('Keep learning'),
        SectionCard(
          onTap: () => ShellNavigation.goTo(ShellNavigation.learn),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                height: 52,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: CircularProgressIndicator(
                        value: _lessonsDone / _lessonsTotal,
                        strokeWidth: 5,
                        strokeCap: StrokeCap.round,
                        backgroundColor: scheme.surfaceContainerHigh,
                      ),
                    ),
                    Text(
                      '$_lessonsDone/$_lessonsTotal',
                      style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _lessonsDone == 0
                          ? 'Start your first lesson'
                          : '$_lessonsDone of $_lessonsTotal signs practised',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Short lessons with camera practice',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ],
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(AppTheme.screenPadding, 16, AppTheme.screenPadding, 28),
          itemCount: sections.length,
          itemBuilder: (context, index) => _FadeIn(index: index, child: sections[index]),
        ),
      ),
    );
  }
}

/// Gentle staggered entrance so the screen settles in rather than popping.
class _FadeIn extends StatelessWidget {
  final int index;
  final Widget child;

  const _FadeIn({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 280 + index.clamp(0, 6) * 50),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(offset: Offset(0, (1 - value) * 14), child: child),
      ),
      child: child,
    );
  }
}

class _Header extends StatelessWidget {
  final String greeting;
  final String profileLabel;
  final VoidCallback onProfileTap;
  final VoidCallback onSettingsTap;

  const _Header({
    required this.greeting,
    required this.profileLabel,
    required this.onProfileTap,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text('Sign & Voice Translator', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: onProfileTap,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_outline, size: 16, color: scheme.onPrimaryContainer),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            profileLabel,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Icon(Icons.expand_more, size: 18, color: scheme.onPrimaryContainer),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        IconButton.filledTonal(
          tooltip: 'Settings',
          onPressed: onSettingsTap,
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  final ProfileExperience experience;

  const _HeroCard({required this.experience});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PressableScale(
      borderRadius: BorderRadius.circular(28),
      onTap: () => experience.openHero(context),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: AppTheme.heroGradient(context),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: AppTheme.navy.withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            children: [
              Positioned(
                right: -18,
                top: -10,
                child: Icon(
                  experience.heroIcon,
                  size: 120,
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'RECOMMENDED FOR YOU',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    experience.heroTitle,
                    style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    experience.heroSubtitle,
                    style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.88)),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(experience.heroIcon, size: 20, color: AppTheme.navy),
                        const SizedBox(width: 8),
                        // Flexible so the label wraps instead of overflowing
                        // when the person has chosen a very large text size.
                        Flexible(
                          child: Text(
                            experience.heroCta,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: AppTheme.navy,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_forward, size: 18, color: AppTheme.navy),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmergencyStrip extends StatelessWidget {
  final VoidCallback onTap;

  const _EmergencyStrip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SectionCard(
      onTap: () {
        SettingsService.instance.hapticTap();
        onTap();
      },
      color: AppTheme.emergency.withValues(alpha: 0.07),
      borderColor: AppTheme.emergency.withValues(alpha: 0.35),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(color: AppTheme.emergency, shape: BoxShape.circle),
            child: const Icon(Icons.emergency, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Emergency alert', style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  'Send your location to your contacts',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _PhraseChip extends StatelessWidget {
  final String text;

  const _PhraseChip({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      borderRadius: BorderRadius.circular(23),
      onTap: () {
        SettingsService.instance.hapticImpact();
        TtsService.instance.speak(text);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(23),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.volume_up_outlined, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
