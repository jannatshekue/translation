import 'package:flutter/material.dart';

import '../../../../core/profile/profile_experience.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../routes/app_routes.dart';
import '../../../../shared/widgets/icon_badge.dart';
import '../../../../shared/widgets/section_card.dart';

/// Shown once, right after the splash screen, only if the person hasn't
/// picked a profile yet. Each option spells out what it changes, so the
/// choice is informed — and nothing is ever hidden: every tool stays
/// available whichever is picked, and it can be changed any time.
class ProfileSelectionScreen extends StatefulWidget {
  const ProfileSelectionScreen({super.key});

  @override
  State<ProfileSelectionScreen> createState() => _ProfileSelectionScreenState();
}

class _ProfileSelectionScreenState extends State<ProfileSelectionScreen> {
  UserProfile? _selected;
  bool _saving = false;

  Future<void> _continue() async {
    final profile = _selected;
    if (profile == null || _saving) return;
    setState(() => _saving = true);
    SettingsService.instance.hapticTap();
    await ProfileExperience.choose(profile, firstRun: true);
    if (mounted) Navigator.of(context).pushReplacementNamed(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppTheme.screenPadding, 28, AppTheme.screenPadding, 12),
                children: [
                  // A list gives its children the full width, so the tile is
                  // aligned explicitly to keep its own size.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: AppTheme.heroGradient(context),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(Icons.sign_language, color: Colors.white, size: 30),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Welcome', style: theme.textTheme.headlineLarge),
                  const SizedBox(height: 8),
                  Text(
                    'How do you communicate?',
                    style: theme.textTheme.titleLarge?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'We set the app up around you. Every tool stays available '
                    'either way, and you can change this later.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  for (final profile in UserProfile.values) ...[
                    _ProfileCard(
                      experience: ProfileExperience.of(profile),
                      selected: _selected == profile,
                      onTap: () {
                        SettingsService.instance.hapticTap();
                        setState(() => _selected = profile);
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppTheme.screenPadding, 8, AppTheme.screenPadding, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selected == null || _saving ? null : _continue,
                  child: Text(_selected == null ? 'Choose one to continue' : 'Continue'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final ProfileExperience experience;
  final bool selected;
  final VoidCallback onTap;

  const _ProfileCard({required this.experience, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SectionCard(
      onTap: onTap,
      borderColor: selected ? scheme.primary : null,
      color: selected ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(experience.icon),
              const SizedBox(width: 14),
              Expanded(
                child: Text(experience.label, style: theme.textTheme.titleMedium),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  key: ValueKey(selected),
                  color: selected ? scheme.primary : scheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            experience.blurb,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: selected
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final perk in experience.perks)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.check, size: 18, color: scheme.secondary),
                                const SizedBox(width: 8),
                                Expanded(child: Text(perk, style: theme.textTheme.bodyMedium)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
