import 'package:flutter/material.dart';

import '../../../../core/services/backup_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/services/sign_classifier_service.dart';
import '../../../../shared/widgets/app_background.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../shared/widgets/section_card.dart';

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

  Widget _sectionLabel(BuildContext context, String text, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            text,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AppBackground(
        child: AnimatedBuilder(
          animation: SettingsService.instance,
          builder: (context, _) {
            final settings = SettingsService.instance;
            return SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _sectionLabel(context, 'Accessibility profile', Icons.accessibility_new),
                  SectionCard(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: RadioGroup<UserProfile>(
                      groupValue: settings.userProfile,
                      onChanged: (value) {
                        settings.hapticTap();
                        if (value != null) settings.setUserProfile(value, applyDefaults: false);
                      },
                      child: const Column(
                        children: [
                          RadioListTile<UserProfile>(
                            title: Text('Hearing & speaking'),
                            subtitle: Text('No special accommodations needed'),
                            value: UserProfile.normal,
                          ),
                          RadioListTile<UserProfile>(
                            title: Text('Hearing disability'),
                            subtitle: Text('Prioritizes visual signs and text'),
                            value: UserProfile.hearingImpaired,
                          ),
                          RadioListTile<UserProfile>(
                            title: Text('Cannot speak'),
                            subtitle: Text('Prioritizes signs and typed speech'),
                            value: UserProfile.speechImpaired,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _sectionLabel(context, 'Sign language', Icons.sign_language_outlined),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Which trained sign vocabulary Sign Recognition should '
                          'try first, alongside your Custom Signs and the built-in '
                          'gesture set.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        SegmentedButton<SignLanguage>(
                          segments: const [
                            ButtonSegment(
                              value: SignLanguage.asl,
                              label: Text('ASL'),
                            ),
                            ButtonSegment(
                              value: SignLanguage.ksl,
                              label: Text('KSL'),
                            ),
                          ],
                          selected: {settings.signLanguage},
                          onSelectionChanged: (selection) {
                            settings.hapticTap();
                            settings.setSignLanguage(selection.first);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _sectionLabel(context, 'Appearance', Icons.palette_outlined),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Theme', style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 8),
                        SegmentedButton<AppThemeMode>(
                          segments: const [
                            ButtonSegment(
                              value: AppThemeMode.light,
                              label: Text('Light'),
                              icon: Icon(Icons.light_mode),
                            ),
                            ButtonSegment(
                              value: AppThemeMode.dark,
                              label: Text('Dark'),
                              icon: Icon(Icons.dark_mode),
                            ),
                            ButtonSegment(
                              value: AppThemeMode.automatic,
                              label: Text('Auto'),
                              icon: Icon(Icons.schedule),
                            ),
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
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
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
                              : const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 12),
                        Text('Text size', style: Theme.of(context).textTheme.bodyMedium),
                        Slider(
                          value: settings.textScale,
                          min: 0.8,
                          max: 1.6,
                          divisions: 8,
                          label: settings.textScale.toStringAsFixed(1),
                          onChanged: (value) => settings.setTextScale(value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _sectionLabel(context, 'Alerts', Icons.notifications_active_outlined),
                  SectionCard(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('High contrast'),
                          subtitle: const Text('Higher-contrast colors throughout the app'),
                          value: settings.highContrast,
                          onChanged: (value) => settings.setHighContrast(value),
                        ),
                        SwitchListTile(
                          title: const Text('Vibration alerts'),
                          subtitle: const Text('Vibrate on recognition and alerts'),
                          value: settings.vibrationEnabled,
                          onChanged: (value) => settings.setVibrationEnabled(value),
                        ),
                        SwitchListTile(
                          title: const Text('Flash alerts'),
                          subtitle: const Text('Flash the screen on recognition and alerts'),
                          value: settings.flashAlertsEnabled,
                          onChanged: (value) => settings.setFlashAlertsEnabled(value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _sectionLabel(context, 'Backup & restore', Icons.backup_outlined),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Custom signs and saved phrases live only on this device. '
                          'Export a backup before uninstalling, or to move them to another phone.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: PressableScale(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _exportData(context),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Theme.of(context).colorScheme.outlineVariant,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.upload, size: 18),
                                      SizedBox(width: 8),
                                      Text('Export'),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: PressableScale(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _importData(context),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Theme.of(context).colorScheme.outlineVariant,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.download, size: 18),
                                      SizedBox(width: 8),
                                      Text('Import'),
                                    ],
                                  ),
                                ),
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
      ),
    );
  }
}
