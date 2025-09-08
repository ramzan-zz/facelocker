// lib/screens/recognize_and_unlock.dart
import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

// Optional Provider fallback (remove if not used)
import '../app_state.dart';

enum UnlockPhase {
  openingCamera,
  warmingUp,
  capturing,
  recognizing,
  resolvingLocker,
  unlocking,
  waitingAck,
  success,
  error,
}

class RecognizeAndUnlockScreen extends StatefulWidget {
  const RecognizeAndUnlockScreen({
    super.key,
    required this.backendBase,
    required this.mqttHost,
    required this.mqttPort,
    required this.siteId,
    this.mqttUsername,
    this.mqttPassword,
  });

  final String backendBase; // e.g. http://192.168.70.14:8000
  final String mqttHost; // e.g. 192.168.70.14
  final int mqttPort; // e.g. 1883
  final String siteId; // e.g. site-001
  final String? mqttUsername;
  final String? mqttPassword;

  static const route = '/unlock';

  @override
  State<RecognizeAndUnlockScreen> createState() =>
      _RecognizeAndUnlockScreenState();
}

class _RecognizeAndUnlockScreenState extends State<RecognizeAndUnlockScreen> {
  // Camera
  CameraController? _cam;
  late Future<void> _camInit;
  bool _camOpened = false; // true only while controller is alive

  // Autofocus nudging
  Timer? _afNudgeTimer;
  bool _afLikelySupported = false;

  // State & UI
  UnlockPhase _phase = UnlockPhase.openingCamera;
  String _status = 'Opening camera…';
  String? _errorText;

  Map<String, dynamic>? _lastRecognizeRaw;
  String? _recognizedUserId;
  String? _recognizedDisplayName;
  int? _unlockedLockerId;

  // Success countdown
  Timer? _successTimer;
  int _countdownSecs = 10;

  // MQTT
  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _sub;
  String? _pendingRequestId;
  Timer? _ackTimeout;

  // Navigation/lifecycle guards
  bool _navigatingAway = false;

  // ───────────────────────── Helpers: UI ─────────────────────────
  Widget _buildNonDistortingPreview() {
    if (!_camOpened || _cam == null || !_cam!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    // camera.value.aspectRatio is width/height in *landscape* terms.
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final ar = _cam!.value.aspectRatio; // e.g., 16/9
    final previewAR = isPortrait ? (1 / ar) : ar; // flip for portrait

    return Center(
      child: AspectRatio(
        aspectRatio: previewAR,
        child: CameraPreview(_cam!),
      ),
    );
  }

  // ───────────────────────── Helpers: AF nudge ─────────────────────────
  Future<void> _startAFNudge() async {
    // Try enabling AF/AE and metering on center
    try {
      await _cam!.setFocusMode(FocusMode.auto);
      await _cam!.setExposureMode(ExposureMode.auto);
      await _cam!.setFocusPoint(const Offset(0.5, 0.5));
      await _cam!.setExposurePoint(const Offset(0.5, 0.5));
      _afLikelySupported = true;
    } catch (_) {
      _afLikelySupported = false; // many front cams are fixed-focus
    }

    // Nudge AF/AE a few times while preview stabilizes (~1.8s)
    int ticks = 0;
    _afNudgeTimer?.cancel();
    _afNudgeTimer =
        Timer.periodic(const Duration(milliseconds: 300), (t) async {
      if (!mounted || _navigatingAway || _cam == null) {
        t.cancel();
        return;
      }
      ticks++;
      if (_afLikelySupported) {
        try {
          await _cam!.setFocusMode(FocusMode.auto);
          await _cam!.setExposureMode(ExposureMode.auto);
          await _cam!.setFocusPoint(const Offset(0.5, 0.5));
          await _cam!.setExposurePoint(const Offset(0.5, 0.5));
        } catch (_) {
          // ignore if unsupported
        }
      }
      if (ticks >= 6) t.cancel(); // ~1.8s total
    });
  }

  void _safeSet(VoidCallback fn) {
    if (!mounted || _navigatingAway) return;
    setState(fn);
  }

  Future<bool> _isUserActive(String userId) async {
    try {
      final r =
          await http.get(Uri.parse('${widget.backendBase}/api/users/$userId'));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body);
        final v = _extractActiveFromUserJson(j);
        if (v != null) return v;
        // If the server returns a user but no status flag, fail closed.
        return false;
      }
      if (r.statusCode == 404) return false; // deleted/nonexistent user
    } catch (_) {}
    // Network/parse errors → fail closed to prevent unauthorized unlock
    return false;
  }

  bool? _extractActiveFromUserJson(dynamic m) {
    Map<String, dynamic>? obj;
    if (m is Map<String, dynamic>) {
      obj = m;
    } else if (m is List && m.isNotEmpty && m.first is Map<String, dynamic>) {
      obj = m.first as Map<String, dynamic>;
    }
    if (obj == null) return null;

    final activeLike = obj['active'] ?? obj['is_active'] ?? obj['enabled'];
    if (activeLike is bool) return activeLike;
    if (activeLike is num) return activeLike != 0;
    if (activeLike is String) {
      final s = activeLike.toLowerCase().trim();
      if (['false', '0', 'no', 'disabled', 'inactive'].contains(s))
        return false;
      if (['true', '1', 'yes', 'enabled', 'active'].contains(s)) return true;
    }

    final status = (obj['status'] ?? obj['user_status'] ?? obj['state'])
        ?.toString()
        .toLowerCase()
        .trim();

    if (status != null) {
      // Important: check negatives first so "inactive" doesn't match "active".
      if (status.contains('disabled') || status.contains('inactive'))
        return false;
      if (status == 'active' || status.startsWith('active')) return true;
    }
    return null;
  }

  // ───────────────────────── Lifecycle ─────────────────────────
  @override
  void initState() {
    super.initState();
    _initCameraAndRun();
  }

  @override
  void dispose() {
    // Block all future UI updates immediately.
    _navigatingAway = true;

    // Stop timers first.
    _afNudgeTimer?.cancel();
    _ackTimeout?.cancel();
    _successTimer?.cancel();

    // Prevent MQTT callbacks from touching UI during teardown.
    if (_client != null) {
      _client!.onConnected = null;
      _client!.onDisconnected = null;
    }
    _sub?.cancel();
    _client?.disconnect();

    // Tear down camera last.
    _camOpened = false;
    final cam = _cam;
    _cam = null;
    cam?.dispose();

    super.dispose();
  }

  // ───────────────────────── Flow ─────────────────────────
  Future<void> _initCameraAndRun() async {
    _safeSet(() {
      _phase = UnlockPhase.openingCamera;
      _status = 'Opening camera…';
      _errorText = null;
      _lastRecognizeRaw = null;
      _recognizedUserId = null;
      _recognizedDisplayName = null;
      _unlockedLockerId = null;
    });

    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () =>
            cameras.isNotEmpty ? cameras.first : (throw 'No camera found'),
      );

      _cam = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      _camInit = _cam!.initialize();
      await _camInit;
      _camOpened = true;

      try {
        await _cam!.setZoomLevel(1.0);
      } catch (_) {}

      await _startAFNudge();

      if (!mounted || _navigatingAway) return;
      _safeSet(() {
        _phase = UnlockPhase.warmingUp;
        _status = _afLikelySupported ? 'Focusing…' : 'Preparing…';
      });

      if (_afLikelySupported) {
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // ✅ Re-check after the delay to avoid calling setState on a disposed widget
      if (!mounted || _navigatingAway) return;

      await _recognizeWithRetries();
    } catch (e) {
      if (!mounted || _navigatingAway) return;
      _safeSet(() {
        _phase = UnlockPhase.error;
        _errorText = 'Camera error: $e';
      });
    }
  }

  /// Take up to 3 shots with small delays to let AF/AE settle before showing errors.
  Future<void> _recognizeWithRetries() async {
    const maxTries = 3;
    for (int attempt = 1; attempt <= maxTries; attempt++) {
      try {
        // Small per-attempt settle time (first attempt already had warm-up)
        if (attempt > 1) {
          _safeSet(() {
            _phase = UnlockPhase.warmingUp;
            _status = 'Adjusting camera… (try $attempt/$maxTries)';
          });
          await Future.delayed(const Duration(milliseconds: 450));
        }

        await _captureRecognizeAndMaybeUnlock();
        // If we reached here without throwing, we either succeeded or moved to next phase.
        return;
      } catch (e) {
        // If it's the last attempt, show error; otherwise loop and retry.
        if (attempt == maxTries) {
          if (!mounted) return;
          _safeSet(() {
            _phase = UnlockPhase.error;
            _errorText = (e.toString().contains('Face not recognized'))
                ? 'Face not recognized. Please scan again.'
                : e.toString();
          });
        }
      }
    }
  }

  Future<void> _captureRecognizeAndMaybeUnlock() async {
    // Capture
    _safeSet(() {
      _phase = UnlockPhase.capturing;
      _status = 'Capturing…';
      _errorText = null;
    });

    // Stop AF nudging once we capture
    _afNudgeTimer?.cancel();

    if (!_camOpened || _cam == null) {
      throw Exception('Camera not ready.');
    }
    final shot = await _cam!.takePicture();

    // Recognize
    _safeSet(() {
      _phase = UnlockPhase.recognizing;
      _status = 'Scanning…';
    });

    final uri = Uri.parse('${widget.backendBase}/api/recognize');
    final req = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('image', shot.path));
    final resp = await req.send();
    final body = await resp.stream.bytesToString();
    if (resp.statusCode != 200) {
      throw Exception('recognize ${resp.statusCode}: $body');
    }
    final data = jsonDecode(body) as Map<String, dynamic>;
    _lastRecognizeRaw = data;

    final faces = (data['faces'] as List?) ?? [];
    if (faces.isEmpty || faces.first is! Map || faces.first['best'] == null) {
      throw Exception('Face not recognized. Please scan again.');
    }

    final best = faces.first['best'] as Map<String, dynamic>;
    final userId = best['user_id']?.toString() ?? '';
    if (userId.isEmpty) {
      throw Exception('Face recognized but user_id missing.');
    }
    _recognizedUserId = userId;
    _recognizedDisplayName = await _resolveUserDisplayName(best, userId);

    // ── Access control first (fail closed if disabled/unverifiable)
    _safeSet(() {
      _status = 'Checking access…';
    });
    final isActive = await _isUserActive(userId);
    if (!isActive) {
      throw Exception('Access denied: this user is disabled.');
    }

    // ── Now resolve locker (only for active users)
    _safeSet(() {
      _phase = UnlockPhase.resolvingLocker;
      _status =
          'Welcome ${_recognizedDisplayName ?? userId} — resolving your locker…';
    });

    final lockerId = await _resolveLockerId(userId);
    if (lockerId == null) {
      throw Exception('No active locker assignment for $userId');
    }
    _unlockedLockerId = lockerId;

    // MQTT Unlock
    _safeSet(() {
      _phase = UnlockPhase.unlocking;
      _status = 'Unlocking locker $lockerId…';
    });

    await _ensureMqtt();
    final requestId = const Uuid().v4();
    final payload = jsonEncode({
      'site_id': widget.siteId,
      'locker_id': lockerId,
      'user_id': userId,
      'action': 'unlock',
      'duration_ms': 1200,
      'request_id': requestId,
      'ttl_ms': 5000,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'source': 'tablet',
    });

    final topic = 'sites/${widget.siteId}/locker/cmd';
    final builder = MqttClientPayloadBuilder()..addUTF8String(payload);
    _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);

    _safeSet(() {
      _pendingRequestId = requestId;
      _phase = UnlockPhase.waitingAck;
      _status = 'Unlock sent → waiting for door event…';
    });

    _ackTimeout?.cancel();
    _ackTimeout = Timer(const Duration(seconds: 5), () {
      if (!mounted || _navigatingAway) return;
      if (_pendingRequestId != null) {
        _safeSet(() {
          _phase = UnlockPhase.error;
          _errorText = 'Unlock sent, but no door event within 5s.';
          _pendingRequestId = null;
        });
      }
    });
  }

  // ───────────────────────── MQTT ─────────────────────────
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

    c.onConnected = () {
      if (!mounted || _navigatingAway) return;
      _safeSet(() => _status = 'MQTT connected');
    };
    c.onDisconnected = () {
      if (!mounted || _navigatingAway) return;
      _safeSet(() => _status = 'MQTT disconnected');
    };

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

    final doorTopic = 'sites/${widget.siteId}/locker/door';
    c.subscribe(doorTopic, MqttQos.atLeastOnce);
    _sub?.cancel();
    _sub = c.updates?.listen((events) {
      for (final m in events) {
        final recMess = m.payload as MqttPublishMessage;
        final pt =
            MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        try {
          final j = jsonDecode(pt) as Map<String, dynamic>;
          final rid = j['request_id']?.toString();
          if (rid != null && rid == _pendingRequestId) {
            _ackTimeout?.cancel();
            _pendingRequestId = null;

            if (!mounted || _navigatingAway) return;
            _safeSet(() {
              _phase = UnlockPhase.success;
              _status =
                  'Welcome, ${_recognizedDisplayName ?? _recognizedUserId}! '
                  'Your locker ${_unlockedLockerId ?? ''} is unlocked.';
              _countdownSecs = 10;
            });

            _startSuccessCountdown();
          }
        } catch (_) {
          // ignore non-JSON payloads
        }
      }
    });

    _client = c;
  }

  // ───────────────────────── Navigation ─────────────────────────
  void _startSuccessCountdown() {
    _successTimer?.cancel();
    _successTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _navigatingAway) return;
      _safeSet(() => _countdownSecs--);
      if (_countdownSecs <= 0) {
        t.cancel();
        _navigateHome();
      }
    });
  }

  void _navigateHome() {
    if (_navigatingAway) return;
    _navigatingAway = true;

    // Clean up aggressively to avoid any late setStates
    _ackTimeout?.cancel();
    _successTimer?.cancel();
    _sub?.cancel();
    _client?.disconnect();
    _afNudgeTimer?.cancel();

    // Null out controller before dispose so UI won't deref it
    _camOpened = false;
    final cam = _cam;
    _cam = null;
    cam?.dispose();

    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  // ───────────────────────── Name/Locker resolution ─────────────────────────
  // Replace _resolveUserDisplayName and _extractNameFromUserJson with these:

  Future<String> _resolveUserDisplayName(
    Map<String, dynamic> best,
    String userId,
  ) async {
    // 1) Try to get a human-friendly name straight from the recognize payload
    final fromBest = _pickName(best);
    if (fromBest != null && fromBest.trim().isNotEmpty) {
      return fromBest.trim();
    }

    // 2) Try your backend (robust to either object or list responses)
    //    a) /api/users/{user_id}
    try {
      final r =
          await http.get(Uri.parse('${widget.backendBase}/api/users/$userId'));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body);
        final n = _pickName(j);
        if (n != null && n.trim().isNotEmpty) return n.trim();
      }
    } catch (_) {}

    //    b) /api/users?user_id={user_id}
    try {
      final r = await http
          .get(Uri.parse('${widget.backendBase}/api/users?user_id=$userId'));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body);
        final n = _pickName(j);
        if (n != null && n.trim().isNotEmpty) return n.trim();
      }
    } catch (_) {}

    // 3) Last resort: show the raw user_id
    return userId;
  }

  /// Picks the best display name from a dynamic JSON shape.
  /// Priority: username > name > display_name > full_name > "first last".
  String? _pickName(dynamic m) {
    Map<String, dynamic>? obj;

    if (m is Map<String, dynamic>) {
      obj = m;
    } else if (m is List && m.isNotEmpty && m.first is Map<String, dynamic>) {
      obj = m.first as Map<String, dynamic>;
    }
    if (obj == null) return null;

    // Prefer `username` first (your request), then common name fields.
    for (final k in ['username', 'name', 'display_name', 'full_name']) {
      final v = obj[k];
      if (v is String && v.trim().isNotEmpty) return v;
    }

    final f = (obj['first_name'] ?? '').toString().trim();
    final l = (obj['last_name'] ?? '').toString().trim();
    final full = '$f ${l.isEmpty ? '' : l}'.trim();
    return full.isNotEmpty ? full : null;
  }

  /// Fast path: use your backend resolver
  Future<int?> _resolveLockerId(String userId) async {
    try {
      final r = await http.get(
        Uri.parse(
            '${widget.backendBase}/api/assignments/current?user_id=$userId'),
      );
      if (r.statusCode == 200) {
        final m = jsonDecode(r.body);
        final raw = m['locker_id'];
        if (raw is int) return raw;
        if (raw is String) return int.tryParse(raw);
      }
    } catch (_) {}
    // Fallback if the resolver isn't available
    return _resolveLockerIdFallback(userId);
  }

  /// Fallback: robust multi-shape resolver you already had
  Future<int?> _resolveLockerIdFallback(String userId) async {
    final base = '${widget.backendBase}/api/assignments/';

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

    // Optional Provider fallback
    try {
      final app = Provider.of<AppState>(context, listen: false);
      final lid = app.assignment[userId];
      if (lid != null) return lid;
    } catch (_) {}
    return null;
  }

  // ───────────────────────── UI ─────────────────────────
  @override
  Widget build(BuildContext context) {
    final preview = (_camOpened && _cam != null && _cam!.value.isInitialized)
        ? _buildNonDistortingPreview()
        : const Center(child: CircularProgressIndicator());

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Live camera preview
            Positioned.fill(child: preview),

            // Gradient top for readability
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                child: Container(
                  height: 140,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),

            // Face guide
            IgnorePointer(
              child: Center(
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.72,
                  height: MediaQuery.of(context).size.width * 0.92,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: Colors.white70, width: 2),
                  ),
                ),
              ),
            ),

            // Status chip
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  _phase == UnlockPhase.error
                      ? const Icon(Icons.error_outline, color: Colors.redAccent)
                      : const Icon(Icons.lock_open, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _phase == UnlockPhase.error
                          ? (_errorText ?? 'Error')
                          : _status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                      ),
                    ),
                  ),
                  if (_phase == UnlockPhase.recognizing ||
                      _phase == UnlockPhase.resolvingLocker ||
                      _phase == UnlockPhase.unlocking ||
                      _phase == UnlockPhase.waitingAck)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
            ),

            // Success banner with countdown
            if (_phase == UnlockPhase.success)
              Positioned(
                left: 16,
                right: 16,
                bottom: 110,
                child: _SuccessCard(
                  name: _recognizedDisplayName ?? _recognizedUserId ?? 'User',
                  lockerId: _unlockedLockerId,
                  seconds: _countdownSecs,
                  onReturnNow: _navigateHome,
                ),
              ),

            // Error/help banner
            if (_phase == UnlockPhase.error)
              Positioned(
                left: 16,
                right: 16,
                bottom: 110,
                child: _ErrorCard(
                  message: _errorText ??
                      'Please ensure your face is fully in the frame and well lit.',
                  onScanAgain: () async {
                    _safeSet(() {
                      _phase = UnlockPhase.warmingUp;
                      _status = 'Adjusting camera…';
                      _errorText = null;
                    });
                    await Future.delayed(const Duration(milliseconds: 300));
                    if (!mounted || _navigatingAway) return;
                    await _recognizeWithRetries();
                  },
                ),
              ),

            // Bottom controls
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: Row(
                children: [
                  // Back / Cancel
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white70),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _navigateHome,
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('Home'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Scan again (available outside success)
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white24,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: (_phase == UnlockPhase.success)
                          ? null
                          : () async {
                              _safeSet(() {
                                _phase = UnlockPhase.warmingUp;
                                _status = 'Adjusting camera…';
                                _errorText = null;
                              });
                              await Future.delayed(
                                  const Duration(milliseconds: 300));
                              if (!mounted || _navigatingAway) return;
                              await _recognizeWithRetries();
                            },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Scan again'),
                    ),
                  ),
                ],
              ),
            ),

            // Optional: tiny JSON debug
            if (_lastRecognizeRaw != null && _phase != UnlockPhase.success)
              Positioned(
                left: 12,
                right: 12,
                bottom: 86,
                child: Opacity(
                  opacity: 0.7,
                  child: Text(
                    jsonEncode(_lastRecognizeRaw),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Cards ─────────────────────────
class _SuccessCard extends StatelessWidget {
  const _SuccessCard({
    required this.name,
    required this.lockerId,
    required this.seconds,
    required this.onReturnNow,
  });

  final String name;
  final int? lockerId;
  final int seconds;
  final VoidCallback onReturnNow;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.green.shade600.withOpacity(0.95),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: const [
              Icon(Icons.check_circle, color: Colors.white, size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Welcome!',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              'Hello, $name — your locker ${lockerId ?? ''} is unlocked.',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  'Returning to Home in $seconds s…',
                  style: const TextStyle(color: Colors.white70),
                ),
                const Spacer(),
                TextButton(
                  onPressed: onReturnNow,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: const Text('Return now'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.message,
    required this.onScanAgain,
  });

  final String message;
  final VoidCallback onScanAgain;

  @override
  Widget build(BuildContext context) {
    final lower = message.toLowerCase();
    final computedTitle = lower.contains('access denied')
        ? 'Access denied'
        : lower.contains('no active locker')
            ? 'No active locker'
            : 'Face not recognized';

    return Card(
      color: Colors.red.shade600.withOpacity(0.95),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  computedTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              message.isEmpty
                  ? 'Please ensure your face is fully inside the frame and well lit, then try again.'
                  : message,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onScanAgain,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text('Scan again',
                    style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
