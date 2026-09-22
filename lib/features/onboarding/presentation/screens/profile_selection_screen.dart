import 'package:flutter/material.dart';

import '../../../../core/services/settings_service.dart';
import '../../../../routes/app_routes.dart';
import '../../../../shared/widgets/app_background.dart';
import '../../../../shared/widgets/pressable_scale.dart';

class _ProfileOption {
  final UserProfile profile;
  final String title;
  final String description;
  final IconData icon;

  const _ProfileOption(this.profile, this.title, this.description, this.icon);
}

const _options = [
  _ProfileOption(
    UserProfile.normal,
    'Hearing & speaking',
    'I can hear and speak normally',
    Icons.person_outline,
  ),
  _ProfileOption(
    UserProfile.hearingImpaired,
    'Hearing disability',
    'I am deaf or hard of hearing',
    Icons.hearing_disabled,
  ),
  _ProfileOption(
    UserProfile.speechImpaired,
    'Cannot speak',
    'I can hear, but cannot speak or vocalize',
    Icons.record_voice_over_outlined,
  ),
];

/// Shown once, right after the splash screen, only if the user hasn't
/// picked a profile yet. Sets accessibility defaults (vibration, flash
/// alerts) and which parts of the app are emphasized first — never hides
/// any feature from anyone regardless of what's picked here.
class ProfileSelectionScreen extends StatelessWidget {
  const ProfileSelectionScreen({super.key});

  Future<void> _choose(BuildContext context, UserProfile profile) async {
    SettingsService.instance.hapticTap();
    await SettingsService.instance.setUserProfile(profile);
    if (context.mounted) {
      Navigator.of(context).pushReplacementNamed(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'How would you like the\napp to work for you?',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'This sets helpful defaults for you — every feature stays '
                  'available either way, and you can change this later in Settings.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 32),
                for (final option in _options) ...[
                  _ProfileCard(option: option, onTap: () => _choose(context, option.profile)),
                  const SizedBox(height: 14),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final _ProfileOption option;
  final VoidCallback onTap;

  const _ProfileCard({required this.option, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PressableScale(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Material(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(option.icon, color: colorScheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      option.description,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
