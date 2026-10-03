import 'package:flutter/material.dart';

import '../../../../core/services/backup_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../routes/app_routes.dart';
import '../../../../core/profile/profile_experience.dart';
import '../../../../shared/widgets/icon_badge.dart';
import '../../../../shared/widgets/profile_sheet.dart';
import '../../../../shared/widgets/section_card.dart';
import '../../../../shared/widgets/section_header.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _pickDayStart(BuildContext context, SettingsService settings) async {
    final picked = await showTimePicker(context: context, initialTime: settings.dayStart);
    if (picked != null) await settings.setDayStart(picked);
  }

  Future<void> _pickNightStart(BuildContext context, SettingsService settings) async {
    final picked = await showTimePicker(context: context, initialTime: settings.nightStart);
    if (picked != null) await settings.setNightStart(picked);
  }

  Future<void> _exportData(BuildContext context) async {
    SettingsService.instance.hapticTap();
    try {
      await BackupService.instance.exportData();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Future<void> _importData(BuildContext context) async {
    SettingsService.instance.hapticTap();
    try {
      final result = await BackupService.instance.importData();
      if (!context.mounted) return;
      if (!result.imported) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${result.signsCount} custom sign(s) and ${result.phrasesCount} phrase(s)',
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AnimatedBuilder(
        animation: SettingsService.instance,
        builder: (context, _) {
          final settings = SettingsService.instance;
          final experience = ProfileExperience.of(settings.userProfile);

          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(AppTheme.screenPadding, 4, AppTheme.screenPadding, 28),
              children: [
                const SectionHeader('Profile'),
                SectionCard(
                  onTap: () => showProfileSheet(context),
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
                      Text('Change', style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary)),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const SectionHeader('Appearance'),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Theme', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 10),
                      SegmentedButton<AppThemeMode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: AppThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                          ButtonSegment(value: AppThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
                          ButtonSegment(value: AppThemeMode.automatic, label: Text('Auto'), icon: Icon(Icons.schedule)),
                        ],
                        selected: {settings.themeMode},
                        onSelectionChanged: (selection) {
                          settings.hapticTap();
                          settings.setThemeMode(selection.first);
                        },
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        child: settings.themeMode == AppThemeMode.automatic
                            ? Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Column(
                                  children: [
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text('Switch to light at'),
                                      trailing: Text(settings.dayStart.format(context)),
                                      onTap: () => _pickDayStart(context, settings),
                                    ),
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text('Switch to dark at'),
                                      trailing: Text(settings.nightStart.format(context)),
                                      onTap: () => _pickNightStart(context, settings),
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                      const Divider(height: 32),
                      Row(
                        children: [
                          Expanded(child: Text('Text size', style: theme.textTheme.titleSmall)),
                          Text(
                            '${(settings.textScale * 100).round()}%',
                            style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                      Slider(
                        value: settings.textScale,
                        min: 0.8,
                        max: 1.6,
                        divisions: 8,
                        label: '${(settings.textScale * 100).round()}%',
                        onChanged: (value) => settings.setTextScale(value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const SectionHeader('Accessibility & alerts'),
                SectionCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('High contrast'),
                        subtitle: const Text('Stronger colours throughout the app'),
                        value: settings.highContrast,
                        onChanged: (value) => settings.setHighContrast(value),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      SwitchListTile(
                        title: const Text('Vibration alerts'),
                        subtitle: const Text('Vibrate on recognition and alerts'),
                        value: settings.vibrationEnabled,
                        onChanged: (value) => settings.setVibrationEnabled(value),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      SwitchListTile(
                        title: const Text('Flash alerts'),
                        subtitle: const Text('Flash the screen on recognition and alerts'),
                        value: settings.flashAlertsEnabled,
                        onChanged: (value) => settings.setFlashAlertsEnabled(value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const SectionHeader('Quick phrases'),
                SectionCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Show on Home'),
                        subtitle: const Text('Tap a phrase to say it aloud, right from Home'),
                        value: settings.quickPhrasesOnHome ?? experience.showQuickPhrases,
                        onChanged: (value) => settings.setQuickPhrasesOnHome(value),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        title: const Text('Manage saved phrases'),
                        subtitle: const Text('Add, edit or remove the phrases you say often'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).pushNamed(AppRoutes.savedPhrases),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const SectionHeader('Backup & restore'),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Custom signs and saved phrases live only on this device. '
                        'Export a backup before uninstalling, or to move them to another phone.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _exportData(context),
                              icon: const Icon(Icons.upload_outlined),
                              label: const Text('Export'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _importData(context),
                              icon: const Icon(Icons.download_outlined),
                              label: const Text('Import'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
