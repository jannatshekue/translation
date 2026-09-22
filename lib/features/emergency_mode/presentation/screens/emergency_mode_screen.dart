import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/services/emergency_sms_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/utils/flash_alert.dart';
import '../../../../core/utils/permission_primer.dart';
import '../../../../models/emergency_contact.dart';
import '../../../../shared/widgets/app_background.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../shared/widgets/section_card.dart';

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
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulse = Tween(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
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

  Future<void> _addOrEditContact({EmergencyContact? existing, int? index}) async {
    final labelController = TextEditingController(text: existing?.label ?? '');
    final numberController = TextEditingController(text: existing?.number ?? '');

    final result = await showDialog<EmergencyContact>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Add contact' : 'Edit contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelController,
              decoration: const InputDecoration(labelText: 'Label (e.g. Mom, Police)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: numberController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final label = labelController.text.trim();
              final number = numberController.text.trim();
              if (number.isEmpty) return;
              Navigator.of(context).pop(
                EmergencyContact(label: label.isEmpty ? number : label, number: number),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null) return;
    SettingsService.instance.hapticTap();
    setState(() {
      if (index != null) {
        _contacts[index] = result;
      } else {
        _contacts.add(result);
      }
    });
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send emergency alert?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This will be sent to:'),
            const SizedBox(height: 8),
            for (final contact in _contacts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('• ${contact.label} (${contact.number})'),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _extraNumberController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Also send to (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Message: ${_messageController.text.trim().isEmpty ? _defaultMessage : _messageController.text.trim()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Send now'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;
    await _sendAlert();
  }

  Future<void> _sendAlert() async {
    final locationGranted = await PermissionPrimer.requestWithRationale(
      context,
      permission: Permission.locationWhenInUse,
      title: 'Location access',
      message: 'Emergency Mode includes your current location in the alert so help can find you.',
    );
    if (!locationGranted) return;
    if (!mounted) return;
    final smsGranted = await PermissionPrimer.requestWithRationale(
      context,
      permission: Permission.sms,
      title: 'Send SMS',
      message: 'Emergency Mode sends your alert as a text message to your emergency contacts.',
    );
    if (!smsGranted) return;

    final extraNumber = _extraNumberController.text.trim();
    final phoneNumbers = [
      ..._contacts.map((c) => c.number),
      if (extraNumber.isNotEmpty) extraNumber,
    ];

    setState(() => _isSending = true);
    try {
      await EmergencySmsService.instance.sendAlert(
        phoneNumbers: phoneNumbers,
        message: _messageController.text.trim().isEmpty
            ? _defaultMessage
            : _messageController.text.trim(),
      );
      SettingsService.instance.hapticSuccess();
      if (mounted) {
        FlashAlert.trigger(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Emergency alert sent')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send alert: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _extraNumberController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid = Platform.isAndroid;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Emergency Mode'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AppBackground(
        child: SafeArea(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    if (!isAndroid)
                      Container(
                        padding: const EdgeInsets.all(14),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          'Emergency SMS is only available on Android. '
                          'iOS does not allow apps to send SMS programmatically.',
                          style: TextStyle(color: colorScheme.onErrorContainer),
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Contacts',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colorScheme.onSurfaceVariant,
                              ),
                        ),
                        PressableScale(
                          borderRadius: BorderRadius.circular(20),
                          onTap: isAndroid ? () => _addOrEditContact() : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            child: Row(
                              children: [
                                Icon(Icons.add, size: 18, color: colorScheme.primary),
                                Text(
                                  ' Add contact',
                                  style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < _contacts.length; i++) ...[
                      Material(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        elevation: 1,
                        shadowColor: Colors.black.withValues(alpha: 0.1),
                        child: ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          leading: Icon(Icons.contact_phone_outlined, color: colorScheme.primary),
                          title: Text(_contacts[i].label, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(_contacts[i].number),
                          onTap: isAndroid ? () => _addOrEditContact(existing: _contacts[i], index: i) : null,
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline, color: colorScheme.error),
                            onPressed: isAndroid ? () => _deleteContact(i) : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 16),
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _messageController,
                            enabled: isAndroid,
                            minLines: 2,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: 'Alert message',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: PressableScale(
                              borderRadius: BorderRadius.circular(12),
                              onTap: isAndroid ? _saveMessage : null,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                decoration: BoxDecoration(
                                  border: Border.all(color: colorScheme.outlineVariant),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text('Save'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                    Center(
                      child: ScaleTransition(
                        scale: isAndroid && !_isSending ? _pulse : const AlwaysStoppedAnimation(1.0),
                        child: PressableScale(
                          borderRadius: BorderRadius.circular(90),
                          onTap: isAndroid && !_isSending ? _handleSendPressed : null,
                          child: Container(
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFEF5350), Color(0xFFB71C1C)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.withValues(alpha: 0.4),
                                  blurRadius: 30,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: Center(
                              child: _isSending
                                  ? const SizedBox(
                                      width: 32,
                                      height: 32,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                                    )
                                  : Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(Icons.emergency, color: Colors.white, size: 40),
                                        SizedBox(height: 8),
                                        Text(
                                          'SEND\nALERT',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            height: 1.2,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
