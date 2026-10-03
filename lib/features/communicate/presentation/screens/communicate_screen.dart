import 'package:flutter/material.dart';

import '../../../../core/profile/app_tools.dart';
import '../../../../core/profile/profile_experience.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/action_tile.dart';
import '../../../../shared/widgets/section_header.dart';

/// Every way of communicating, grouped by the situation you're in rather than
/// by technology. Groups and the rows inside them are ordered for the
/// person's profile, and the tools meant for them are tagged "For you".
class CommunicateScreen extends StatelessWidget {
  const CommunicateScreen({super.key});

  static const _groups = <_Group>[
    _Group('With signs', 'Use the camera to understand and produce signs', [
      AppTool.signRecognition,
      AppTool.customSigns,
    ]),
    _Group('With speech and text', 'Turn speech into text, or text into speech', [
      AppTool.speechToText,
      AppTool.textToSpeech,
      AppTool.savedPhrases,
    ]),
    _Group('With another person', 'Translate between two people', [
      AppTool.conversation,
      AppTool.connectDevices,
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: SettingsService.instance,
          builder: (context, _) {
            final experience = ProfileExperience.of(SettingsService.instance.userProfile);
            int rank(AppTool tool) => experience.toolOrder.indexOf(tool);

            // Order the groups by their best-ranked tool, and the tools
            // inside each group the same way.
            final ordered = [
              for (final g in _groups)
                _Group(g.title, g.subtitle, [...g.tools]..sort((a, b) => rank(a).compareTo(rank(b)))),
            ]..sort((a, b) => rank(a.tools.first).compareTo(rank(b.tools.first)));

            return ListView(
              padding: const EdgeInsets.fromLTRB(AppTheme.screenPadding, 16, AppTheme.screenPadding, 28),
              children: [
                Text('Communicate', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text(
                  'Choose how you want to talk right now.',
                  style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                for (final group in ordered) ...[
                  SectionHeader(group.title),
                  ActionGroup(
                    children: [
                      for (final tool in group.tools)
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
                  const SizedBox(height: 24),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Group {
  final String title;
  final String subtitle;
  final List<AppTool> tools;

  const _Group(this.title, this.subtitle, this.tools);
}
