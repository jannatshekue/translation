import 'dart:convert';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/services/contact_picker_service.dart';
import '../../../../core/services/emergency_sms_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/services/starter_phrases.dart';
import '../../../../core/services/tts_service.dart';
import '../../../../core/utils/flash_alert.dart';
import '../../../../core/utils/app_permissions.dart';
import '../../../../models/emergency_contact.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/section_card.dart';
import '../../../../shared/widgets/section_header.dart';

const _defaultMessage = 'I need help. This is an emergency.';
const _defaultContact = EmergencyContact(label: 'Emergency services', number: '112');
const _contactsPrefsKey = 'emergency_contacts';
const _messagePrefsKey = 'emergency_message';

class EmergencyModeScreen extends StatefulWidget {
  const EmergencyModeScreen({super.key});

  @override
  State<EmergencyModeScreen> createState() => _EmergencyModeScreenState();
}

class _EmergencyModeScreenState extends State<EmergencyModeScreen>
    with SingleTickerProviderStateMixin {
  final _messageController = TextEditingController(text: _defaultMessage);
  final _extraNumberController = TextEditingController();
  List<EmergencyContact> _contacts = [];
  bool _isSending = false;
  bool _loaded = false;

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_contactsPrefsKey);
    final contacts = raw == null
        ? <EmergencyContact>[_defaultContact]
        : (jsonDecode(raw) as List<dynamic>)
            .map((e) => EmergencyContact.fromJson(e as Map<String, dynamic>))
            .toList();
    if (raw == null) {
      await prefs.setString(_contactsPrefsKey, jsonEncode(contacts.map((c) => c.toJson()).toList()));
    }
    setState(() {
      _contacts = contacts;
      _messageController.text = prefs.getString(_messagePrefsKey) ?? _defaultMessage;
      _loaded = true;
    });
  }

  Future<void> _saveContacts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contactsPrefsKey, jsonEncode(_contacts.map((c) => c.toJson()).toList()));
  }

  Future<void> _saveMessage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_messagePrefsKey, _messageController.text.trim());
    SettingsService.instance.hapticTap();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alert message saved')),
      );
    }
  }

  /// Opens the phone's own contact picker. Returns null (after telling the
  /// person why, if something went wrong) when nothing was chosen.
  Future<PickedContact?> _pickFromPhonebook() async {
    try {
      return await ContactPickerService.instance.pickContact();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is StateError ? e.message : 'Could not open the phonebook.')),
        );
      }
      return null;
    }
  }

  Future<void> _addOrEditContact({EmergencyContact? existing, int? index}) async {
    final labelController = TextEditingController(text: existing?.label ?? '');
    final numberController = TextEditingController(text: existing?.number ?? '');
    String? numberError;

    final result = await showDialog<EmergencyContact>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Add contact' : 'Edit contact'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.contacts_outlined),
                  label: const Text('Choose from phonebook'),
                  onPressed: () async {
                    final picked = await _pickFromPhonebook();
                    if (picked == null) return;
                    setDialogState(() {
                      numberController.text = picked.number;
                      if (picked.name.isNotEmpty) labelController.text = picked.name;
                      numberError = null;
                    });
                  },
                ),
                const SizedBox(height: 8),
                const Center(child: Text('or type it in')),
                const SizedBox(height: 8),
                TextField(
                  controller: labelController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Label (e.g. Mom, Police)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: numberController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: 'Phone number', errorText: numberError),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final number = normalizePhoneNumber(numberController.text);
                if (number == null) {
                  setDialogState(() => numberError = 'Enter a valid phone number');
                  return;
                }
                final label = labelController.text.trim();
                Navigator.of(context).pop(
                  (existing ?? const EmergencyContact(label: '', number: ''))
                      .copyWith(label: label.isEmpty ? number : label, number: number),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    SettingsService.instance.hapticTap();
    setState(() {
      if (index != null) {
        _contacts[index] = result;
      } else {
        // The stock "Emergency services 112" entry is only a placeholder for
        // a fresh install. Once the person adds their own contact, stop
        // sending to it by default (it stays in the list, untouched, and can
        // be ticked back on) — otherwise every alert also goes to a number
        // they never chose.
        for (var i = 0; i < _contacts.length; i++) {
          if (_isStockDefault(_contacts[i])) _contacts[i] = _contacts[i].copyWith(selected: false);
        }
        _contacts.add(result);
      }
    });
    await _saveContacts();
  }

  bool _isStockDefault(EmergencyContact c) =>
      c.number == _defaultContact.number && c.label == _defaultContact.label;

  Future<void> _toggleSelected(int index, bool value) async {
    setState(() => _contacts[index] = _contacts[index].copyWith(selected: value));
    await _saveContacts();
  }

  Future<void> _deleteContact(int index) async {
    SettingsService.instance.hapticTap();
    setState(() => _contacts.removeAt(index));
    await _saveContacts();
  }

  Future<void> _handleSendPressed() async {
    if (_contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one emergency contact first')),
      );
      return;
    }

    _extraNumberController.clear();
    // Work on a local copy of the ticks so Cancel leaves the saved choice alone.
    final ticked = [for (final c in _contacts) c.selected];
    String? extraError;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Send emergency alert?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Choose who receives it:'),
                const SizedBox(height: 4),
                for (var i = 0; i < _contacts.length; i++)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: ticked[i],
                    onChanged: (v) => setDialogState(() => ticked[i] = v ?? false),
                    title: Text(_contacts[i].label),
                    subtitle: Text(_contacts[i].number),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: _extraNumberController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Also send to another number (optional)',
                    border: const OutlineInputBorder(),
                    errorText: extraError,
                    suffixIcon: IconButton(
                      tooltip: 'Choose from phonebook',
                      icon: const Icon(Icons.contacts_outlined),
                      onPressed: () async {
                        final picked = await _pickFromPhonebook();
                        if (picked == null) return;
                        setDialogState(() {
                          _extraNumberController.text = picked.number;
                          extraError = null;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Message: ${_messageController.text.trim().isEmpty ? _defaultMessage : _messageController.text.trim()}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                final extraText = _extraNumberController.text.trim();
                if (extraText.isNotEmpty && normalizePhoneNumber(extraText) == null) {
                  setDialogState(() => extraError = 'Enter a valid phone number');
                  return;
                }
                if (!ticked.contains(true) && extraText.isEmpty) {
                  setDialogState(() => extraError = 'Tick a contact or enter a number');
                  return;
                }
                Navigator.of(context).pop(true);
              },
              child: const Text('Send now'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < _contacts.length; i++) {
        _contacts[i] = _contacts[i].copyWith(selected: ticked[i]);
      }
    });
    await _saveContacts();
    if (!mounted) return;
    await _sendAlert();
  }

  Future<void> _sendAlert() async {
    // Location improves the alert but must never block it: if the person
    // declines (or it's unavailable) the message still goes out without it.
    await AppPermissions.ensure(context, Permission.locationWhenInUse, announceDenial: false);
    if (!mounted) return;
    // Sending needs SMS. If it is refused nothing is sent and a short message
    // says so; there is no further box and no second ask.
    final smsGranted = await AppPermissions.ensure(context, Permission.sms);
    if (!smsGranted) return;

    final recipients = <String, String>{
      for (final c in _contacts)
        if (c.selected) c.number: c.label,
    };
    final extraNumber = normalizePhoneNumber(_extraNumberController.text);
    if (extraNumber != null) recipients.putIfAbsent(extraNumber, () => extraNumber);

    setState(() => _isSending = true);
    try {
      final report = await EmergencySmsService.instance.sendAlert(
        phoneNumbers: recipients.keys.toList(),
        message: _messageController.text.trim().isEmpty
            ? _defaultMessage
            : _messageController.text.trim(),
      );
      if (!mounted) return;
      if (report.anySucceeded) {
        SettingsService.instance.hapticSuccess();
        FlashAlert.trigger(context);
      }
      await _showResultDialog(
        success: report.allSucceeded,
        title: report.allSucceeded
            ? 'Alert sent'
            : report.anySucceeded
                ? 'Alert partly sent'
                : 'Alert not sent',
        report: report,
        names: recipients,
      );
    } catch (e) {
      if (mounted) {
        await _showResultDialog(
          success: false,
          title: 'Alert not sent',
          body: e is StateError ? e.message : e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _showResultDialog({
    required bool success,
    required String title,
    String? body,
    SmsAlertReport? report,
    Map<String, String> names = const {},
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    String nameOf(String number) => names[number] == number ? number : '${names[number] ?? number} ($number)';

    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          success ? Icons.check_circle : Icons.error_outline,
          color: success ? Colors.green : colorScheme.error,
          size: 40,
        ),
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (body != null) Text(body),
              if (report != null) ...[
                for (final number in report.sent)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check, color: Colors.green, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Sent to ${nameOf(number)}')),
                      ],
                    ),
                  ),
                for (final entry in report.failed.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.close, color: colorScheme.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Not sent to ${nameOf(entry.key)}: ${entry.value}')),
                      ],
                    ),
                  ),
                if (report.anySucceeded && !report.locationIncluded) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Your location could not be found, so it was not included.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _extraNumberController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  List<EmergencyContact> get _selected => [for (final c in _contacts) if (c.selected) c];

  @override
  Widget build(BuildContext context) {
    // defaultTargetPlatform (not dart:io) so layout tests can run this as Android.
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = _selected;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(AppTheme.screenPadding, 16, AppTheme.screenPadding, 28),
                children: [
                  Text('Emergency', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Texts your location to the people you choose.',
                    style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 20),
                  if (!isAndroid)
                    Container(
                      padding: const EdgeInsets.all(14),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'Emergency SMS is only available on Android. '
                        'iOS does not allow apps to send SMS programmatically.',
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),
                  Center(
                    child: _SosButton(
                      pulse: _pulseController,
                      enabled: isAndroid,
                      sending: _isSending,
                      onTap: _handleSendPressed,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _RecipientSummary(selected: selected, onChoose: _handleSendPressed),
                  const SizedBox(height: 28),
                  // For when someone nearby can help: the phone says it for you.
                  const SectionHeader('Say it aloud'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final phrase in StarterPhrases.emergencySpoken)
                        ActionChip(
                          avatar: Icon(Icons.volume_up_outlined, size: 18, color: scheme.primary),
                          label: Text(phrase),
                          onPressed: () {
                            SettingsService.instance.hapticImpact();
                            TtsService.instance.speak(phrase);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  SectionHeader(
                    'Emergency contacts',
                    actionLabel: isAndroid ? 'Add' : null,
                    onAction: isAndroid ? () => _addOrEditContact() : null,
                  ),
                  if (_contacts.isEmpty)
                    SectionCard(
                      child: Text(
                        'No contacts yet. Add the people who should be told when you need help.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    )
                  else
                    SectionCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < _contacts.length; i++) ...[
                            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                            ListTile(
                              contentPadding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
                              leading: Checkbox(
                                value: _contacts[i].selected,
                                onChanged: isAndroid ? (v) => _toggleSelected(i, v ?? false) : null,
                              ),
                              title: Text(_contacts[i].label, style: theme.textTheme.titleMedium),
                              subtitle: Text(_contacts[i].number),
                              onTap: isAndroid ? () => _addOrEditContact(existing: _contacts[i], index: i) : null,
                              trailing: IconButton(
                                tooltip: 'Remove',
                                icon: Icon(Icons.delete_outline, color: scheme.error),
                                onPressed: isAndroid ? () => _deleteContact(i) : null,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 6),
                    child: Text(
                      'Tick the contacts who should receive the alert.',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const SectionHeader('Alert message'),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _messageController,
                          enabled: isAndroid,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(hintText: 'What should the alert say?'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your location link is added automatically.',
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.tonal(
                            onPressed: isAndroid ? _saveMessage : null,
                            child: const Text('Save message'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// "Will notify: …" line under the SOS button, so it's always clear who an
/// alert would reach before anyone presses anything.
class _RecipientSummary extends StatelessWidget {
  final List<EmergencyContact> selected;
  final VoidCallback onChoose;

  const _RecipientSummary({required this.selected, required this.onChoose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (selected.isEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'No one is selected to receive the alert',
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Text(
          'Will notify',
          style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in selected)
              Chip(
                avatar: Icon(Icons.person, size: 18, color: scheme.primary),
                label: Text(c.label),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ],
    );
  }
}

/// The emergency button. A solid red disc with a soft pulsing halo, a bold
/// "SOS" and a plain-language hint — unmistakable, but calm enough not to
/// shout at someone who is not in danger. The halo stops while sending.
class _SosButton extends StatelessWidget {
  final Animation<double> pulse;
  final bool enabled;
  final bool sending;
  final VoidCallback onTap;

  const _SosButton({
    required this.pulse,
    required this.enabled,
    required this.sending,
    required this.onTap,
  });

  static const double _size = 176;
  static const double _area = 252;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = enabled && !sending;
    final base = enabled ? AppTheme.emergency : scheme.outline;

    return Semantics(
      button: true,
      enabled: active,
      label: 'Send emergency alert',
      child: SizedBox(
        width: _area,
        height: _area,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (active)
              AnimatedBuilder(
                animation: pulse,
                builder: (context, _) => Stack(
                  alignment: Alignment.center,
                  children: [
                    for (final offset in const [0.0, 0.5]) _halo((pulse.value + offset) % 1.0, base),
                  ],
                ),
              ),
            // Static soft ring so the button reads as one object even at rest.
            Container(
              width: _size + 30,
              height: _size + 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: base.withValues(alpha: 0.10),
              ),
            ),
            PressableScale(
              borderRadius: BorderRadius.circular(_size / 2),
              onTap: active
                  ? () {
                      SettingsService.instance.hapticImpact();
                      onTap();
                    }
                  : null,
              child: Container(
                width: _size,
                height: _size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.3, -0.4),
                    radius: 1.0,
                    colors: enabled
                        ? const [Color(0xFFE53935), AppTheme.emergency, AppTheme.emergencyDeep]
                        : [scheme.outlineVariant, scheme.outline, scheme.outline],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 5),
                  boxShadow: [
                    BoxShadow(
                      color: base.withValues(alpha: 0.45),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Center(
                  child: sending
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 34,
                              height: 34,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3.5),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'SENDING…',
                              textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2),
                              maxLines: 1,
                              softWrap: false,
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: Colors.white,
                                    letterSpacing: 1.6,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // "SOS" is a fixed-size mark on a fixed-size disc, so it
                            // ignores the text-size setting (it would otherwise
                            // wrap letter by letter). The caption below still
                            // grows with the setting, up to what the disc holds.
                            const Text(
                              'SOS',
                              textScaler: TextScaler.noScaling,
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 52,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 3,
                                height: 1.0,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'TAP TO SEND',
                              textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2),
                              maxLines: 1,
                              softWrap: false,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    letterSpacing: 1.6,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One expanding, fading ring of the halo. [t] runs 0 → 1.
  Widget _halo(double t, Color color) {
    final diameter = _size + 20 + (_area - _size - 20) * t;
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.40 * (1 - t)), width: 3),
      ),
    );
  }
}
