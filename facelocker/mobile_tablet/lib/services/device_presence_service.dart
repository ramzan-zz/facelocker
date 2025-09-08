// lib/services/device_presence_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class DeviceConfig {
  final String id;
  final String label;
  const DeviceConfig({required this.id, required this.label});
}

class DevicePresence {
  final String id;
  final String label;
  bool online;
  DateTime? lastSeen;
  String? lastAvailability; // 'online' | 'offline' | null

  DevicePresence({
    required this.id,
    required this.label,
    this.online = false,
    this.lastSeen,
    this.lastAvailability,
  });
}

class DevicePresenceService extends ChangeNotifier {
  DevicePresenceService._();
  static final DevicePresenceService instance = DevicePresenceService._();

  late String _host;
  late int _port;
  String? _username;
  String? _password;
  late String _siteId;
  List<DeviceConfig> _devices = const [];
  final Map<String, DevicePresence> _state = {};
  Timer? _gcTimer;

  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _sub;

  // Consider offline if no heartbeat for this long
  Duration heartbeatTimeout = const Duration(seconds: 25);

  /// Call once at app start.
  Future<void> start({
    required String host,
    required int port,
    required String siteId,
    required List<DeviceConfig> devices,
    String? username,
    String? password,
  }) async {
    _host = host;
    _port = port;
    _siteId = siteId;
    _devices = devices;
    _username = username;
    _password = password;

    // Initialize map with known devices
    for (final d in _devices) {
      _state[d.id] = DevicePresence(id: d.id, label: d.label);
    }

    await _ensureMqtt();

    // Periodic health sweep
    _gcTimer?.cancel();
    _gcTimer = Timer.periodic(const Duration(seconds: 5), (_) => _sweep());
  }

  List<DevicePresence> get devices {
    return _devices.map((d) => _state[d.id]!).toList(growable: false);
  }

  @override
  void dispose() {
    _gcTimer?.cancel();
    _sub?.cancel();
    _client?.disconnect();
    super.dispose();
  }

  Future<void> _ensureMqtt() async {
    if (_client != null &&
        _client!.connectionStatus?.state == MqttConnectionState.connected) {
      return;
    }

    final cid = 'presence-$_siteId-${DateTime.now().millisecondsSinceEpoch}';
    final c = MqttServerClient.withPort(_host, cid, _port);
    c.logging(on: false);
    c.keepAlivePeriod = 15;
    c.autoReconnect = true;

    c.onConnected = () {};
    c.onDisconnected = () {};

    final conn = MqttConnectMessage()
        .withClientIdentifier(cid)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    c.connectionMessage = conn;

    try {
      await c.connect(_username, _password);
    } catch (_) {
      c.disconnect();
      // try again in 3s
      Future.delayed(const Duration(seconds: 3), _ensureMqtt);
      return;
    }

    if (c.connectionStatus?.state != MqttConnectionState.connected) {
      // try again in 3s
      Future.delayed(const Duration(seconds: 3), _ensureMqtt);
      return;
    }

    // Subscribe to availability + heartbeat (adjust to your firmware)
    // Expected topics:
    //   sites/{siteId}/devices/{deviceId}/availability  -> "online"|"offline"
    //   sites/{siteId}/devices/{deviceId}/heartbeat    -> any payload, ideally a ts
    final base = 'sites/$_siteId/devices/+/';
    c.subscribe('${base}availability', MqttQos.atLeastOnce);
    c.subscribe('${base}heartbeat', MqttQos.atLeastOnce);

    _sub?.cancel();
    _sub = c.updates?.listen((events) {
      for (final m in events) {
        final rec = m.payload as MqttPublishMessage;
        final topic = m.topic;
        final payload =
            MqttPublishPayload.bytesToStringAsString(rec.payload.message);
        _onMessage(topic, payload);
      }
    });

    _client = c;
  }

  void _onMessage(String topic, String payload) {
    // Parse deviceId from: sites/{siteId}/devices/{deviceId}/{suffix}
    final parts = topic.split('/');
    final deviceIdIdx = parts.indexOf('devices') + 1;
    if (deviceIdIdx <= 0 || deviceIdIdx >= parts.length) return;
    final deviceId = parts[deviceIdIdx];
    final suffix = parts.isNotEmpty ? parts.last : '';

    final dev = _state[deviceId];
    if (dev == null) return; // ignore unknown devices

    if (suffix == 'availability') {
      final p = payload.trim().toLowerCase();
      if (p == 'online' || p == 'offline') {
        dev.lastAvailability = p;
        dev.online = p == 'online';
        dev.lastSeen = DateTime.now();
        notifyListeners();
      }
      return;
    }

    if (suffix == 'heartbeat') {
      dev.lastSeen = DateTime.now();
      // If we never got availability, infer "online" on any heartbeat
      dev.online = true;
      notifyListeners();
      return;
    }

    // Optional: if heartbeat JSON contains ts, you can parse it here
    // try { final j = jsonDecode(payload); ... } catch (_) {}
  }

  void _sweep() {
    final now = DateTime.now();
    bool changed = false;
    for (final dev in _state.values) {
      // If availability explicitly says offline, keep offline
      if (dev.lastAvailability == 'offline') {
        if (dev.online) {
          dev.online = false;
          changed = true;
        }
        continue;
      }

      // If no heartbeat for too long → offline
      final seen = dev.lastSeen;
      final isStale = seen == null || now.difference(seen) > heartbeatTimeout;
      final nextOnline = !isStale;
      if (dev.online != nextOnline) {
        dev.online = nextOnline;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }
}
