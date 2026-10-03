import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../../core/services/device_sync_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/services/stt_service.dart';
import '../../../../core/services/translation_service.dart';
import '../../../../core/services/tts_service.dart';
import '../../../../core/utils/app_permissions.dart';
import '../../../../core/utils/priority_languages.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/section_card.dart';

const _myNameKey = 'device_sync_my_name';
const _rememberedPeerKey = 'device_sync_remembered_peer';
const _idleReminderDelay = Duration(minutes: 5);

/// Real two-phone Conversation Mode: each person has the app on their own
/// device, and this screen pairs the two directly (offline, no server) via
/// Nearby Connections (Bluetooth/WiFi Direct under the hood — see
/// DeviceSyncService), either by scanning the other phone's one-time QR
/// code or, if a device was remembered before, by auto-reconnecting to it.
/// Once paired, speech recognized on one phone is sent to the other, which
/// translates it into its own chosen language and speaks it — replacing
/// the pass-the-single-phone flow in [ConversationScreen] for people who
/// each have their own device.
class DeviceSyncScreen extends StatefulWidget {
  const DeviceSyncScreen({super.key});

  @override
  State<DeviceSyncScreen> createState() => _DeviceSyncScreenState();
}

class _DeviceSyncScreenState extends State<DeviceSyncScreen> {
  final _service = DeviceSyncService.instance;

  SyncConnectionState _state = SyncConnectionState.idle;
  String? _peerName;
  String? _error;
  String _mySessionName = '';
  String? _rememberedPeer;
  bool _rememberThisDevice = false;

  final _nameController = TextEditingController();
  List<LocaleName> _locales = [];
  String _myLocale = 'en-US';

  final List<_ConversationEntry> _log = [];
  bool _isListening = false;
  String _liveText = '';
  final _typedController = TextEditingController();
  bool _longConversationMode = false;
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    _service.onStateChanged = _handleStateChanged;
    _service.onMessageReceived = _handleMessageReceived;
    _service.onIncomingRequest = _handleIncomingRequest;
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString(_myNameKey) ?? '';
    final remembered = prefs.getString(_rememberedPeerKey);
    final locales = sortByPriorityWith(
      await SttService.instance.getAvailableLocalesIfPermitted(),
      (l) => l.localeId,
    );
    if (!mounted) return;
    setState(() {
      _nameController.text = savedName;
      _mySessionName = DeviceSyncService.generateSessionName(savedName);
      _rememberedPeer = remembered;
      _locales = locales;
      if (locales.isNotEmpty) _myLocale = locales.first.localeId;
    });

    // Become discoverable as soon as the screen opens — otherwise a phone
    // just sitting on its own QR code (the "have the other person scan
    // this" side) never calls startAdvertising and is invisible to the
    // other phone's discovery, no matter what that other phone does. This
    // does NOT actively hunt for/request connections to whoever it finds
    // (see DeviceSyncService's class doc) — that only starts once there's
    // a specific target, from a remembered device or a scanned code.
    await _resumeDiscoverability();
  }

  Future<void> _loadLocalesAfterPermission() async {
    final locales = sortByPriorityWith(
      await SttService.instance.getAvailableLocalesIfPermitted(),
      (l) => l.localeId,
    );
    if (!mounted || locales.isEmpty) return;
    setState(() {
      _locales = locales;
      _myLocale = locales.first.localeId;
    });
  }

  /// Starts advertising (or, for a remembered peer, actively re-pairing)
  /// so the phone is reachable again. Called on first opening the screen
  /// and after a manual disconnect.
  Future<void> _resumeDiscoverability() async {
    if (_rememberedPeer != null) {
      await _startPairing(onlyConnectToName: _rememberedPeer!);
    } else {
      await _startAdvertisingOnly();
    }
  }

  void _handleStateChanged(SyncConnectionState state, {String? peerName, String? error}) {
    if (!mounted) return;
    setState(() {
      _state = state;
      if (peerName != null) _peerName = peerName;
      _error = error;
    });
    if (state == SyncConnectionState.connected) {
      SettingsService.instance.hapticSuccess();
      _resetIdleTimer();
    } else {
      _idleTimer?.cancel();
    }
    if (state == SyncConnectionState.disconnected) {
      // An unexpected drop (peer went out of range, closed the app, etc.)
      // — the manual Disconnect button resumes discoverability itself and
      // doesn't reach here (see DeviceSyncService._onDisconnected's
      // endpoint check), so this only covers the case nothing else does.
      _resumeDiscoverability();
    }
  }

  /// Restarts the 2-minute idle-disconnect reminder. Called on connect and
  /// on any conversation activity (sending or receiving a message) so the
  /// clock only really measures silence, not total call length. Disabled
  /// entirely while Long conversation mode is on.
  void _resetIdleTimer() {
    _idleTimer?.cancel();
    if (_state != SyncConnectionState.connected || _longConversationMode) return;
    _idleTimer = Timer(_idleReminderDelay, _showIdleReminder);
  }

  void _showIdleReminder() {
    if (!mounted || _state != SyncConnectionState.connected) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Still connected'),
        content: Text(
          "It's been quiet for 5 minutes with ${_peerName ?? "the other phone"}. "
          'Disconnect to save battery, or stay connected?',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _disconnect();
            },
            child: const Text('Disconnect'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _resetIdleTimer();
            },
            child: const Text('Stay connected'),
          ),
        ],
      ),
    );
  }

  void _toggleLongConversationMode(bool value) {
    setState(() => _longConversationMode = value);
    if (value) {
      _idleTimer?.cancel();
    } else {
      _resetIdleTimer();
    }
  }

  Future<void> _disconnect() async {
    _idleTimer?.cancel();
    await _service.disconnect();
    if (!mounted) return;
    setState(() {
      _peerName = null;
      _log.clear();
      _liveText = '';
    });
    await _resumeDiscoverability();
  }

  void _handleIncomingRequest(String endpointId, String peerName) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text('$peerName wants to connect'),
        content: const Text(
          'Only accept if you recognize this as the specific person/device you meant to pair with.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _service.declineConnection(endpointId);
            },
            child: const Text('Decline'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _service.approveConnection(endpointId);
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  void _handleMessageReceived(SyncMessage message) async {
    final fromLang = TranslationService.languageFor(message.locale);
    final toLang = TranslationService.languageFor(_myLocale);
    String displayText = message.text;
    if (fromLang != null && toLang != null && fromLang != toLang) {
      try {
        displayText = await TranslationService.instance.translate(
          message.text,
          from: fromLang,
          to: toLang,
        );
      } catch (_) {
        // Fall back to the raw text if translation isn't available.
      }
    }
    if (!mounted) return;
    setState(() => _log.add(_ConversationEntry(text: displayText, fromPeer: true)));
    _resetIdleTimer();
    SettingsService.instance.hapticImpact();
    await TtsService.instance.speak(displayText, language: _myLocale);
  }

  Future<bool> _requestSyncPermissions() async {
    if (!mounted) return false;
    // Bluetooth is what the link actually runs on, so all three are
    // required. Location and nearby-Wi-Fi only enable the faster Wi-Fi
    // transport (and location is mandatory on older Androids), so they're
    // requested alongside but don't block pairing.
    return AppPermissions.ensureAll(
      context,
      required: [
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
      ],
      optional: [Permission.location, Permission.nearbyWifiDevices],
      announceDenial: false, // the status bar on this screen shows the message
    );
  }

  Future<void> _startAdvertisingOnly() async {
    final granted = await _requestSyncPermissions();
    if (!granted) {
      setState(() {
        // Shown in the status bar: the feature can't run, and why.
        _state = SyncConnectionState.failed;
        _error = AppPermissions.neededMessage(Permission.bluetoothScan);
      });
      return;
    }
    await _service.startAdvertisingOnly(myDisplayName: _mySessionName);
  }

  Future<void> _startPairing({required String onlyConnectToName}) async {
    final granted = await _requestSyncPermissions();
    if (!granted) {
      setState(() {
        // Shown in the status bar: the feature can't run, and why.
        _state = SyncConnectionState.failed;
        _error = AppPermissions.neededMessage(Permission.bluetoothScan);
      });
      return;
    }
    await _service.startPairing(myDisplayName: _mySessionName, onlyConnectToName: onlyConnectToName);
  }

  Future<void> _saveName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_myNameKey, _nameController.text.trim());
    setState(() => _mySessionName = DeviceSyncService.generateSessionName(_nameController.text));
    SettingsService.instance.hapticTap();

    // The QR code just changed to show the new name — re-advertise under
    // it too, otherwise this phone keeps broadcasting its old name while
    // displaying a QR nobody scanning it can actually find. Only safe to
    // do while nothing's mid-handshake; connected/connecting/awaiting
    // states aren't reachable from this screen anyway (the name field
    // only shows before a connection exists).
    if (_state == SyncConnectionState.idle ||
        _state == SyncConnectionState.searching ||
        _state == SyncConnectionState.failed ||
        _state == SyncConnectionState.disconnected) {
      await _startAdvertisingOnly();
    }
  }

  Future<void> _scanToConnect() async {
    final cameraGranted = await AppPermissions.ensure(context, Permission.camera);
    if (!cameraGranted || !mounted) return;
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScannerScreen()),
    );
    if (scanned == null || scanned.isEmpty) return;
    await _startPairing(onlyConnectToName: scanned);
  }

  Future<void> _toggleRemember(bool value) async {
    setState(() => _rememberThisDevice = value);
    final prefs = await SharedPreferences.getInstance();
    if (value && _peerName != null) {
      await prefs.setString(_rememberedPeerKey, _peerName!);
      setState(() => _rememberedPeer = _peerName);
    } else if (!value) {
      await prefs.remove(_rememberedPeerKey);
      setState(() => _rememberedPeer = null);
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await SttService.instance.stopListening();
      setState(() => _isListening = false);
      return;
    }
    if (!mounted) return;
    final micGranted = await AppPermissions.ensure(context, Permission.microphone);
    if (!micGranted) return;
    await Permission.speech.request();
    final available = await SttService.instance.initialize();
    if (!available) return;
    // The language list stays empty until the microphone is allowed.
    if (_locales.isEmpty) await _loadLocalesAfterPermission();

    setState(() {
      _isListening = true;
      _liveText = '';
    });
    await SttService.instance.startListening(
      (text, isFinal) {
        setState(() => _liveText = text);
        if (isFinal) _sendRecognized(text);
      },
      localeId: _myLocale,
    );
  }

  Future<void> _sendRecognized(String text) async {
    await SttService.instance.stopListening();
    setState(() => _isListening = false);
    if (text.trim().isEmpty) return;
    setState(() => _log.add(_ConversationEntry(text: text, fromPeer: false)));
    _resetIdleTimer();
    await _service.send(SyncMessage(text: text, locale: _myLocale));
  }

  Future<void> _sendTyped() async {
    final text = _typedController.text.trim();
    if (text.isEmpty) return;
    _typedController.clear();
    setState(() => _log.add(_ConversationEntry(text: text, fromPeer: false)));
    _resetIdleTimer();
    await _service.send(SyncMessage(text: text, locale: _myLocale));
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _service.onStateChanged = null;
    _service.onMessageReceived = null;
    _service.onIncomingRequest = null;
    _service.disconnect();
    SttService.instance.stopListening();
    _nameController.dispose();
    _typedController.dispose();
    super.dispose();
  }

  String get _statusText {
    switch (_state) {
      case SyncConnectionState.idle:
        return 'Not connected';
      case SyncConnectionState.searching:
        return 'Waiting to connect — show your code, or scan theirs…';
      case SyncConnectionState.awaitingApproval:
        return '${_peerName ?? "A phone"} wants to connect…';
      case SyncConnectionState.connecting:
        return 'Connecting to ${_peerName ?? "device"}…';
      case SyncConnectionState.connected:
        return 'Connected to ${_peerName ?? "device"}';
      case SyncConnectionState.disconnected:
        return 'Disconnected';
      case SyncConnectionState.failed:
        return _error ?? 'Connection failed';
    }
  }

  Color _statusColor(ColorScheme scheme) {
    switch (_state) {
      case SyncConnectionState.connected:
        return AppTheme.success;
      case SyncConnectionState.failed:
      case SyncConnectionState.disconnected:
        return scheme.error;
      case SyncConnectionState.searching:
      case SyncConnectionState.awaitingApproval:
      case SyncConnectionState.connecting:
        return scheme.primary;
      case SyncConnectionState.idle:
        return scheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final connected = _state == SyncConnectionState.connected;
    final statusColor = _statusColor(scheme);

    return Scaffold(
      appBar: AppBar(title: const Text('Connect devices')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppTheme.screenPadding, 4, AppTheme.screenPadding, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _statusText,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (!connected) ...[
                Text(
                  'Talk with someone on their own phone. Both of you open this screen — '
                  'one shows a code, the other scans it. No internet needed.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Your name', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _nameController,
                              decoration: const InputDecoration(hintText: 'Shown to the other phone'),
                              onSubmitted: (_) => _saveName(),
                              onEditingComplete: _saveName,
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.tonal(
                            style: FilledButton.styleFrom(minimumSize: const Size(72, 54)),
                            onPressed: _saveName,
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Option 1 — let them scan your code', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 14),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: QrImageView(data: _mySessionName, size: 180),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: Text(
                          _mySessionName,
                          style: theme.textTheme.titleMedium?.copyWith(letterSpacing: 1),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Option 2 — scan their code', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _scanToConnect,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scan their code'),
                      ),
                      if (_rememberedPeer != null) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => _startPairing(onlyConnectToName: _rememberedPeer!),
                          icon: const Icon(Icons.history),
                          label: Text('Reconnect to $_rememberedPeer', overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (connected) ...[
                SectionCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Always connect to this device'),
                        subtitle: Text('Skip QR scanning next time with ${_peerName ?? "this phone"}'),
                        value: _rememberThisDevice,
                        onChanged: _toggleRemember,
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      SwitchListTile(
                        title: const Text('Long conversation mode'),
                        subtitle: const Text("Turns off the 'still connected?' reminder."),
                        value: _longConversationMode,
                        onChanged: _toggleLongConversationMode,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (_locales.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: _myLocale,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Your language'),
                    items: [
                      for (final locale in _locales)
                        DropdownMenuItem(value: locale.localeId, child: Text(locale.name)),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _myLocale = value);
                    },
                  ),
                const SizedBox(height: 16),
                Container(
                  constraints: const BoxConstraints(minHeight: 220),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_log.isEmpty && !_isListening)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 60),
                          child: Text(
                            'Connected. Speak or type — it appears on the other phone.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      for (final entry in _log)
                        Align(
                          alignment: entry.fromPeer ? Alignment.centerLeft : Alignment.centerRight,
                          child: Container(
                            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: entry.fromPeer ? scheme.surfaceContainerHigh : scheme.primary,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              entry.text,
                              style: TextStyle(color: entry.fromPeer ? scheme.onSurface : scheme.onPrimary),
                            ),
                          ),
                        ),
                      if (_isListening)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _liveText.isEmpty ? 'Listening…' : _liveText,
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _typedController,
                        decoration: const InputDecoration(hintText: 'Type a message instead…'),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendTyped(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filled(
                      tooltip: 'Send',
                      style: IconButton.styleFrom(minimumSize: const Size(54, 54)),
                      onPressed: _sendTyped,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Center(
                  child: GestureDetector(
                    onTap: _toggleListening,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isListening ? AppTheme.emergency : scheme.primary,
                      ),
                      child: Icon(
                        _isListening ? Icons.stop_rounded : Icons.mic,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _disconnect,
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                    side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationEntry {
  final String text;
  final bool fromPeer;

  const _ConversationEntry({required this.text, required this.fromPeer});
}

class _QrScannerScreen extends StatefulWidget {
  const _QrScannerScreen();

  @override
  State<_QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<_QrScannerScreen> {
  // MobileScanner calls onDetect once per processed camera frame, so a
  // code that stays in view for even a fraction of a second fires this
  // multiple times. Without this guard, a second detection arrives while
  // the first pop's route transition is still in flight and pops again —
  // dismissing the screen underneath (DeviceSyncScreen) along with the
  // scanner, which tore down the sync attempt right after it started.
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan their code')),
      body: MobileScanner(
        errorBuilder: (context, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? 'Camera permission is off. Allow it in Settings to scan a code.'
                  : 'The camera could not be started.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        onDetect: (capture) {
          if (_handled) return;
          for (final barcode in capture.barcodes) {
            final value = barcode.rawValue;
            if (value != null && value.isNotEmpty) {
              _handled = true;
              Navigator.of(context).pop(value);
              return;
            }
          }
        },
      ),
    );
  }
}
