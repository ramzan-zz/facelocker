// lib/screens/recognize_and_unlock.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:uuid/uuid.dart';
import 'package:provider/provider.dart';

// If you have an AppState with a user->locker map, you can optionally
// fall back to it. If not, you can delete the two lines below.
import '../app_state.dart'; // optional; remove if you don't use it.

class RecognizeAndUnlockScreen extends StatefulWidget {
  final String backendBase; // e.g. http://192.168.70.14:8000
  final String mqttHost; // e.g. 192.168.70.14
  final int mqttPort; // e.g. 1883
  final String siteId; // e.g. site-001

  final String? mqttUsername;
  final String? mqttPassword;

  const RecognizeAndUnlockScreen({
    super.key,
    required this.backendBase,
    required this.mqttHost,
    required this.mqttPort,
    required this.siteId,
    this.mqttUsername,
    this.mqttPassword,
  });

  @override
  State<RecognizeAndUnlockScreen> createState() =>
      _RecognizeAndUnlockScreenState();
}

class _RecognizeAndUnlockScreenState extends State<RecognizeAndUnlockScreen> {
  final _picker = ImagePicker();
  XFile? _file;
  bool _busy = false;
  String _status = 'Ready';
  Map<String, dynamic>? _lastResponse;

  // MQTT
  MqttServerClient? _client;
  String? _pendingRequestId;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    _client?.disconnect();
    super.dispose();
  }

  Future<void> _pick() async {
    final x = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 95,
    );
    if (x != null) setState(() => _file = x);
  }

  Future<void> _ensureMqtt() async {
    if (_client != null &&
        _client!.connectionStatus?.state == MqttConnectionState.connected) {
      return;
    }

    final cid =
        'tablet-${widget.siteId}-${DateTime.now().millisecondsSinceEpoch}';
    final c = MqttServerClient.withPort(widget.mqttHost, cid, widget.mqttPort);
    c.logging(on: false);
    c.keepAlivePeriod = 15;
    c.autoReconnect = true;
    c.onConnected = () => setState(() => _status = 'MQTT connected');
    c.onDisconnected = () => setState(() => _status = 'MQTT disconnected');

    final connMess = MqttConnectMessage()
        .withClientIdentifier(cid)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    c.connectionMessage = connMess;

    try {
      await c.connect(widget.mqttUsername, widget.mqttPassword);
    } catch (e) {
      c.disconnect();
      throw Exception('MQTT connect failed: $e');
    }

    if (c.connectionStatus?.state != MqttConnectionState.connected) {
      throw Exception('MQTT not connected: ${c.connectionStatus}');
    }

    // Subscribe to door events to catch ACKs with the same request_id
    final doorTopic = 'sites/${widget.siteId}/locker/door';
    c.subscribe(doorTopic, MqttQos.atLeastOnce);
    _sub = c.updates?.listen((events) {
      for (final m in events) {
        final recMess = m.payload as MqttPublishMessage;
        final pt =
            MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        try {
          final j = jsonDecode(pt) as Map<String, dynamic>;
          final rid = j['request_id']?.toString();
          if (rid != null && rid == _pendingRequestId) {
            setState(() {
              _status = 'Door event received ✅ (request_id matched)';
            });
            _pendingRequestId = null;
          }
        } catch (_) {
          // ignore non-JSON messages on the topic
        }
      }
    });

    _client = c;
  }

  // ---- Assignment resolver (robust to different response shapes)
  Future<int?> _resolveLockerId(String userId) async {
    final base =
        '${widget.backendBase}/api/assignments/'; // trailing slash avoids 307

    List<dynamic> _extractList(dynamic obj) {
      if (obj is List) return obj;
      if (obj is Map) {
        for (final k in ['items', 'results', 'data']) {
          final v = obj[k];
          if (v is List) return v;
        }
      }
      return const [];
    }

    int? _extractLocker(dynamic item) {
      if (item is! Map) return null;
      dynamic v = item['locker_id'] ?? item['lockerId'] ?? item['locker'];
      if (v is int) return v;
      if (v is String) return int.tryParse(v);
      if (v is Map) {
        final vv = v['locker_id'] ?? v['lockerId'];
        if (vv is int) return vv;
        if (vv is String) return int.tryParse(vv);
      }
      return null;
    }

    // Try with active=true
    {
      final r = await http.get(Uri.parse('$base?user_id=$userId&active=true'));
      if (r.statusCode == 200) {
        final list = _extractList(jsonDecode(r.body));
        if (list.isNotEmpty) {
          final lid = _extractLocker(list.first);
          if (lid != null) return lid;
        }
      }
    }

    // Try with is_active=true
    {
      final r =
          await http.get(Uri.parse('$base?user_id=$userId&is_active=true'));
      if (r.statusCode == 200) {
        final list = _extractList(jsonDecode(r.body));
        if (list.isNotEmpty) {
          final lid = _extractLocker(list.first);
          if (lid != null) return lid;
        }
      }
    }

    // Try without filter then pick first for that user
    {
      final r = await http.get(Uri.parse(base));
      if (r.statusCode == 200) {
        final list = _extractList(jsonDecode(r.body));
        for (final it in list) {
          if (it is Map && it['user_id']?.toString() == userId) {
            final lid = _extractLocker(it);
            if (lid != null) return lid;
          }
        }
      }
    }

    // Final fallback: optional AppState mapping (if present)
    try {
      final app = Provider.of<AppState>(context, listen: false);
      final lid = app.assignment[userId];
      if (lid != null) return lid;
    } catch (_) {
      // ignore if AppState/provider not in use
    }

    return null;
  }

  Future<void> _recognizeAndUnlock() async {
    if (_file == null) {
      setState(() => _status = 'Capture a photo first');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Recognizing...';
      _lastResponse = null;
    });

    try {
      // 1) Recognize
      final uri = Uri.parse('${widget.backendBase}/api/recognize');
      final req = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('image', _file!.path));
      final resp = await req.send();
      final body = await resp.stream.bytesToString();
      if (resp.statusCode != 200) {
        throw Exception('recognize ${resp.statusCode}: $body');
      }
      final data = jsonDecode(body) as Map<String, dynamic>;
      _lastResponse = data;

      final faces = (data['faces'] as List?) ?? [];
      if (faces.isEmpty || faces.first['best'] == null) {
        setState(() {
          _busy = false;
          _status = 'No match found';
        });
        return;
      }

      final best = faces.first['best'] as Map<String, dynamic>;
      final userId = best['user_id']?.toString() ?? '';
      final sim = (best['similarity'] ?? '').toString();
      setState(() => _status = 'Recognized $userId (similarity $sim)');

      // 2) Resolve locker_id
      final lockerId = await _resolveLockerId(userId);
      if (lockerId == null) {
        setState(() {
          _busy = false;
          _status = 'No active locker assignment for $userId';
        });
        return;
      }

      // 3) MQTT unlock publish
      await _ensureMqtt();
      final topic = 'sites/${widget.siteId}/locker/cmd';
      final requestId = const Uuid().v4();
      final payload = jsonEncode({
        'site_id': widget.siteId,
        'locker_id': lockerId,
        'user_id': userId,
        'action': 'unlock', // include action for clarity
        'duration_ms': 1200, // pulse length (tune for your relay)
        'request_id': requestId,
        'ttl_ms': 5000,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'source': 'tablet', // who sent this (optional)
      });
      final builder = MqttClientPayloadBuilder()..addUTF8String(payload);
      _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);

      setState(() {
        _pendingRequestId = requestId;
        _status = 'Unlock sent → waiting door event...';
      });

      // Optional: timeout if no door event within 5s
      Future.delayed(const Duration(seconds: 5), () {
        if (!mounted) return;
        if (_pendingRequestId != null) {
          setState(() {
            _status = 'Unlock command sent (no door event within 5s).';
            _pendingRequestId = null;
          });
        }
      });
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final image =
        _file != null ? Image.file(File(_file!.path)) : const SizedBox();
    return Scaffold(
      appBar: AppBar(title: const Text('FaceLocker — Recognize & Unlock')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _file == null ? const Text('Capture a frame') : image,
              ),
            ),
            const SizedBox(height: 12),
            if (_busy) const LinearProgressIndicator(),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _busy ? null : _pick,
                  child: const Text('Capture'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _busy ? null : _recognizeAndUnlock,
                  child: const Text('Recognize & Unlock'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _status,
                style: TextStyle(
                  color: _status.startsWith('Recognized') ? Colors.green : null,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_lastResponse != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  jsonEncode(_lastResponse),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
