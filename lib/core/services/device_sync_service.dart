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

enum SyncConnectionState {
  idle,
  searching,
  awaitingApproval,
  connecting,
  connected,
  disconnected,
  failed,
}

/// Direct, offline device-to-device link for two-person Conversation Mode
/// when each person has their own phone, instead of passing one phone back
/// and forth. Built on Google's Nearby Connections API (via the
/// `nearby_connections` plugin), which negotiates Bluetooth or WiFi Direct
/// automatically — no server, no internet, no pairing cost, matching the
/// app's offline-first requirement.
///
/// A phone is discoverable (advertising) as soon as the screen opens, via
/// [startAdvertisingOnly] — otherwise nobody could ever scan its QR code.
/// But it does NOT actively hunt for and request connections to nearby
/// phones ([startPairing]'s discovery half) until the person has expressed
/// real intent to connect to one specific phone — by scanning its QR code
/// or reconnecting to a remembered device. That split matters in a real
/// public setting (a clinic, a market): if every phone running the app
/// both advertised AND freely discovered/requested at once, phones would
/// cross-connect to whichever stranger's phone happened to be found first
/// instead of the person the user actually meant to pair with.
///
/// [_onlyConnectToName] doubles as the trust signal for incoming requests:
/// a request from that exact name is auto-accepted (the person already
/// expressed intent by scanning/remembering it), but any other incoming
/// request — including ones received while just advertising with no
/// target picked yet — surfaces via [onIncomingRequest] so a human has to
/// explicitly approve it before anything connects.
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
  void Function(String endpointId, String peerName)? onIncomingRequest;

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

  /// Makes this phone discoverable (advertising only, no active discovery)
  /// so someone who scans its QR code can find and request a connection to
  /// it. Does not itself hunt for or request connections to anyone —
  /// see the class doc for why that split matters in a crowd.
  Future<void> startAdvertisingOnly({required String myDisplayName}) async {
    _myDisplayName = myDisplayName;
    _onlyConnectToName = null;
    onStateChanged?.call(SyncConnectionState.searching);

    await stopSearching();

    try {
      await _nearby.startAdvertising(
        myDisplayName,
        Strategy.P2P_STAR,
        serviceId: _serviceId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    } catch (e) {
      onStateChanged?.call(SyncConnectionState.failed, error: e.toString());
    }
  }

  /// Starts advertising AND actively discovering under [myDisplayName],
  /// requesting a connection to the first endpoint whose advertised name
  /// matches [onlyConnectToName] exactly — the name from a scanned QR code
  /// or a remembered device. Only call this once the person has picked a
  /// specific phone to connect to; see the class doc.
  Future<void> startPairing({
    required String myDisplayName,
    required String onlyConnectToName,
  }) async {
    _myDisplayName = myDisplayName;
    _onlyConnectToName = onlyConnectToName;
    onStateChanged?.call(SyncConnectionState.searching);

    // Safe to call while already advertising — e.g. narrowing to a
    // specific scanned peer after the screen's own advertise-only start.
    // Stop first so the plugin doesn't reject a duplicate start.
    await stopSearching();

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
    if (endpointName != _onlyConnectToName) return;

    // requestConnection can throw (observed: PlatformException
    // STATUS_ALREADY_CONNECTED_TO_ENDPOINT, when the native Nearby layer
    // still has a stale connection to this endpoint from a previous
    // session that our own Dart-side state has already moved past).
    // Unhandled, that exception silently kills the attempt with the
    // screen stuck on "searching" and no explanation — surface it as a
    // real failure instead.
    _nearby
        .requestConnection(
      _myDisplayName ?? 'Device',
      endpointId,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
    )
        .catchError((Object e) {
      onStateChanged?.call(
        SyncConnectionState.failed,
        error: 'Could not start the connection. Try scanning again.',
      );
      return false;
    });
  }

  void _onConnectionInitiated(String endpointId, ConnectionInfo info) {
    _connectedPeerName = info.endpointName;
    if (info.endpointName == _onlyConnectToName) {
      // We already expressed explicit intent to connect to exactly this
      // phone (scanned its code, or it's our remembered device) — no need
      // to make the person confirm a second time.
      onStateChanged?.call(SyncConnectionState.connecting, peerName: info.endpointName);
      _nearby.acceptConnection(endpointId, onPayLoadRecieved: _onPayloadReceived);
    } else {
      // Unsolicited — either a stranger's phone found us while we're just
      // advertising with no target picked, or (in principle) a name that
      // doesn't match what we ourselves targeted. Require a human tap
      // before accepting anything.
      onStateChanged?.call(SyncConnectionState.awaitingApproval, peerName: info.endpointName);
      onIncomingRequest?.call(endpointId, info.endpointName);
    }
  }

  /// Accepts an incoming request surfaced via [onIncomingRequest].
  Future<void> approveConnection(String endpointId) async {
    await _nearby.acceptConnection(endpointId, onPayLoadRecieved: _onPayloadReceived);
  }

  /// Declines an incoming request surfaced via [onIncomingRequest] and goes
  /// back to searching (advertising/discovery, whichever was active,
  /// carries on).
  Future<void> declineConnection(String endpointId) async {
    await _nearby.rejectConnection(endpointId);
    onStateChanged?.call(SyncConnectionState.searching);
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
    // Only the CURRENTLY tracked endpoint's drop is real news. A stale
    // event for an endpoint we've already moved on from (e.g. the native
    // confirmation of a disconnect() call arriving after a manual
    // reconnect has already started and cleared _connectedEndpointId)
    // must not clobber whatever newer state we're already in.
    if (_connectedEndpointId != endpointId) return;
    _connectedEndpointId = null;
    _connectedPeerName = null;
    onStateChanged?.call(SyncConnectionState.disconnected);
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
    // Also clear anything the native Nearby layer itself still considers
    // connected, even if it isn't the one endpoint Dart-side state was
    // tracking — otherwise a later requestConnection to the same phone
    // can fail with STATUS_ALREADY_CONNECTED_TO_ENDPOINT even though our
    // own UI already shows "not connected" (observed after a disconnect/
    // reconnect cycle).
    try {
      await _nearby.stopAllEndpoints();
    } catch (_) {
      // Nothing to stop — fine.
    }
    await stopSearching();
    _connectedEndpointId = null;
    _connectedPeerName = null;
  }
}
