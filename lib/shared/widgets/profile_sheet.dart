import 'package:flutter/material.dart';

import '../../core/profile/profile_experience.dart';
import '../../core/services/settings_service.dart';
import 'icon_badge.dart';
import 'section_card.dart';

/// Opens the "How do you communicate?" chooser as a bottom sheet. Used from
/// Home's profile pill and from Settings.
Future<void> showProfileSheet(BuildContext context) {
  SettingsService.instance.hapticTap();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _ProfileSheet(),
  );
}

/// Switch profile. Shows exactly what each choice changes, so the difference
/// is never a mystery.
class _ProfileSheet extends StatelessWidget {
  const _ProfileSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      child: AnimatedBuilder(
        animation: SettingsService.instance,
        builder: (context, _) {
          final current = SettingsService.instance.userProfile;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How do you communicate?', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'This changes what Home puts first. Every tool stays available.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                for (final profile in UserProfile.values) ...[
                  _ProfileOptionCard(
                    experience: ProfileExperience.of(profile),
                    selected: profile == current,
                    onTap: () async {
                      SettingsService.instance.hapticTap();
                      await ProfileExperience.choose(profile, firstRun: false);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProfileOptionCard extends StatelessWidget {
  final ProfileExperience experience;
  final bool selected;
  final VoidCallback onTap;

  const _ProfileOptionCard({required this.experience, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SectionCard(
      onTap: onTap,
      borderColor: selected ? scheme.primary : null,
      color: selected ? scheme.primaryContainer.withValues(alpha: 0.4) : null,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          IconBadge(experience.icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(experience.label, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  experience.blurb,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (selected) Icon(Icons.check_circle, color: scheme.primary),
        ],
      ),
    );
  }
}
