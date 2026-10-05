import 'dart:async';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../models/shared_location.dart';
import 'pairing.dart';

enum SyncState { connecting, online, offline }

/// A location update from the other person; [location] is null when they
/// turned sharing off.
class PartnerUpdate {
  const PartnerUpdate(this.deviceId, this.location);
  final String deviceId;
  final SharedLocation? location;
}

/// Relays encrypted locations between the two devices through an MQTT
/// broker. Messages are retained, so the last known position is delivered
/// as soon as the other person opens the app.
class SyncService {
  SyncService({
    required this.room,
    required this.deviceId,
    this.host = 'broker.emqx.io',
    this.port = 8883,
  });

  final Room room;
  final String deviceId;
  final String host;
  final int port;

  final _states = StreamController<SyncState>.broadcast();
  final _partner = StreamController<PartnerUpdate>.broadcast();

  Stream<SyncState> get states => _states.stream;
  Stream<PartnerUpdate> get partnerUpdates => _partner.stream;

  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;
  Timer? _retry;
  bool _disposed = false;

  // What the retained message on the broker should be: a location, or
  // "stopped" (empty). Re-sent whenever the connection comes back.
  SharedLocation? _latest;
  bool _stopped = false;
  final _lastSeen = <String, DateTime>{};

  String get _myTopic => '${room.topic}/$deviceId';

  bool get _connected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> connect() async {
    if (_disposed) return;
    _retry?.cancel();
    _emit(SyncState.connecting);

    final client = MqttServerClient.withPort(host, 'bn$deviceId', port)
      ..secure = true
      ..keepAlivePeriod = 30
      ..autoReconnect = true
      ..resubscribeOnAutoReconnect = true
      ..logging(on: false);
    client.connectionMessage =
        MqttConnectMessage().withClientIdentifier('bn$deviceId').startClean();
    client.onAutoReconnect = () => _emit(SyncState.connecting);
    client.onAutoReconnected = () {
      _emit(SyncState.online);
      _flush();
    };
    client.onDisconnected = () => _emit(SyncState.offline);
    _client = client;

    try {
      await client.connect();
    } catch (_) {
      client.disconnect();
    }
    if (_disposed) {
      client.disconnect();
      return;
    }
    if (!_connected) {
      // autoReconnect only covers drops after a first successful connect.
      _emit(SyncState.offline);
      _retry = Timer(const Duration(seconds: 5), connect);
      return;
    }

    _updatesSub = client.updates!.listen(_onMessages);
    client.subscribe('${room.topic}/+', MqttQos.atLeastOnce);
    _emit(SyncState.online);
    _flush();
  }

  void publish(SharedLocation location) {
    _latest = location;
    _stopped = false;
    _flush();
  }

  /// Removes my position from the broker and tells the other person.
  void publishStopped() {
    _latest = null;
    _stopped = true;
    _flush();
  }

  Future<void> _flush() async {
    if (!_connected) return;
    final location = _latest;
    final builder = MqttClientPayloadBuilder();
    if (location != null) {
      builder.addString(await room.encrypt(location.toJson(), deviceId));
      if (!_connected || !identical(location, _latest)) return;
    } else if (!_stopped) {
      return;
    }
    _client!.publishMessage(
      _myTopic,
      MqttQos.atLeastOnce,
      builder.payload!,
      retain: true,
    );
  }

  Future<void> _onMessages(List<MqttReceivedMessage<MqttMessage>> events) async {
    for (final event in events) {
      final sender = event.topic.split('/').last;
      final message = event.payload;
      if (sender == deviceId || message is! MqttPublishMessage) continue;

      final bytes = message.payload.message;
      if (bytes.isEmpty) {
        _partner.add(PartnerUpdate(sender, null));
        continue;
      }
      final json = await room.decrypt(
        MqttPublishPayload.bytesToStringAsString(bytes),
        sender,
      );
      if (json == null || _disposed) continue;
      final SharedLocation location;
      try {
        location = SharedLocation.fromJson(json);
      } catch (_) {
        continue;
      }
      final seen = _lastSeen[sender];
      if (seen != null && location.time.isBefore(seen)) continue;
      _lastSeen[sender] = location.time;
      _partner.add(PartnerUpdate(sender, location));
    }
  }

  void _emit(SyncState state) {
    if (!_disposed) _states.add(state);
  }

  Future<void> dispose() async {
    _disposed = true;
    _retry?.cancel();
    await _updatesSub?.cancel();
    _client?.autoReconnect = false;
    _client?.disconnect();
    await _states.close();
    await _partner.close();
  }
}
