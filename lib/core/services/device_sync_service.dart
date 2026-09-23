import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:nearby_connections/nearby_connections.dart';

/// A message relayed to the paired device: recognized speech plus the
/// locale it was spoken in, so the receiver can translate it into their own
/// chosen language before displaying/speaking it.
class SyncMessage {
  final String text;
  final String locale;

  const SyncMessage({required this.text, required this.locale});

  factory SyncMessage.fromJson(Map<String, dynamic> json) => SyncMessage(
        text: json['text'] as String,
        locale: json['locale'] as String,
      );

  Map<String, dynamic> toJson() => {'text': text, 'locale': locale};
}

enum SyncConnectionState { idle, searching, connecting, connected, disconnected, failed }

/// Direct, offline device-to-device link for two-person Conversation Mode
/// when each person has their own phone, instead of passing one phone back
/// and forth. Built on Google's Nearby Connections API (via the
/// `nearby_connections` plugin), which negotiates Bluetooth or WiFi Direct
/// automatically — no server, no internet, no pairing cost, matching the
/// app's offline-first requirement.
///
/// Both sides advertise AND discover simultaneously under the same
/// [_serviceId] so either phone can be the one that notices the other
/// first — there's no separate "host" vs "join" role to pick, which would
/// be an awkward extra step for two people just trying to talk to each
/// other. [startPairing]'s `onlyConnectToName` narrows this down to one
/// specific nearby phone (from a scanned QR code or a remembered device),
/// which matters because in a real public setting — a clinic, a market —
/// there may be several other phones advertising nearby.
class DeviceSyncService {
  DeviceSyncService._internal();

  static final DeviceSyncService instance = DeviceSyncService._internal();

  static const _serviceId = 'com.umma.translation.devicesync';

  final Nearby _nearby = Nearby();
  String? _connectedEndpointId;
  String? _connectedPeerName;
  String? _myDisplayName;
  String? _onlyConnectToName;

  void Function(SyncConnectionState state, {String? peerName, String? error})? onStateChanged;
  void Function(SyncMessage message)? onMessageReceived;

  bool get isConnected => _connectedEndpointId != null;
  String? get connectedPeerName => _connectedPeerName;

  /// Generates a short, single-use pairing code appended to a human name —
  /// e.g. "Jannat-4F82". New every time this is called, so an old
  /// screenshotted QR code stops being a valid way to connect once a fresh
  /// pairing attempt starts (the "unique code per connection" ask).
  static String generateSessionName(String humanName) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    final code = List.generate(4, (_) => chars[rand.nextInt(chars.length)]).join();
    final base = humanName.trim().isEmpty ? 'Device' : humanName.trim();
    return '$base-$code';
  }

  /// Starts advertising and discovering under [myDisplayName]. If
  /// [onlyConnectToName] is set, discovered endpoints are ignored unless
  /// their advertised name matches exactly — used both for QR-scanned
  /// one-time codes and for a remembered device's stored name.
  Future<void> startPairing({
    required String myDisplayName,
    String? onlyConnectToName,
  }) async {
    _myDisplayName = myDisplayName;
    _onlyConnectToName = onlyConnectToName;
    onStateChanged?.call(SyncConnectionState.searching);

    try {
      await _nearby.startAdvertising(
        myDisplayName,
        Strategy.P2P_STAR,
        serviceId: _serviceId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
      await _nearby.startDiscovery(
        myDisplayName,
        Strategy.P2P_STAR,
        serviceId: _serviceId,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: (_) {},
      );
    } catch (e) {
      onStateChanged?.call(SyncConnectionState.failed, error: e.toString());
    }
  }

  void _onEndpointFound(String endpointId, String endpointName, String serviceId) {
    if (_connectedEndpointId != null) return;
    final target = _onlyConnectToName;
    if (target != null && endpointName != target) return;

    _nearby.requestConnection(
      _myDisplayName ?? 'Device',
      endpointId,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
    );
  }

  void _onConnectionInitiated(String endpointId, ConnectionInfo info) {
    onStateChanged?.call(SyncConnectionState.connecting, peerName: info.endpointName);
    _connectedPeerName = info.endpointName;
    _nearby.acceptConnection(endpointId, onPayLoadRecieved: _onPayloadReceived);
  }

  void _onConnectionResult(String endpointId, Status status) {
    if (status == Status.CONNECTED) {
      _connectedEndpointId = endpointId;
      _nearby.stopAdvertising();
      _nearby.stopDiscovery();
      onStateChanged?.call(SyncConnectionState.connected, peerName: _connectedPeerName);
    } else {
      onStateChanged?.call(SyncConnectionState.failed, error: 'Connection rejected or errored.');
    }
  }

  void _onDisconnected(String endpointId) {
    if (_connectedEndpointId == endpointId || _connectedEndpointId == null) {
      _connectedEndpointId = null;
      _connectedPeerName = null;
      onStateChanged?.call(SyncConnectionState.disconnected);
    }
  }

  void _onPayloadReceived(String endpointId, Payload payload) {
    if (payload.type != PayloadType.BYTES || payload.bytes == null) return;
    try {
      final decoded = jsonDecode(utf8.decode(payload.bytes!)) as Map<String, dynamic>;
      onMessageReceived?.call(SyncMessage.fromJson(decoded));
    } catch (_) {
      // Malformed/foreign payload on our service ID — ignore it.
    }
  }

  Future<void> send(SyncMessage message) async {
    final endpointId = _connectedEndpointId;
    if (endpointId == null) return;
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(message.toJson())));
    await _nearby.sendBytesPayload(endpointId, bytes);
  }

  /// Stops advertising/discovery without dropping an existing connection.
  Future<void> stopSearching() async {
    await _nearby.stopAdvertising();
    await _nearby.stopDiscovery();
  }

  Future<void> disconnect() async {
    final endpointId = _connectedEndpointId;
    if (endpointId != null) {
      await _nearby.disconnectFromEndpoint(endpointId);
    }
    await stopSearching();
    _connectedEndpointId = null;
    _connectedPeerName = null;
  }
}
