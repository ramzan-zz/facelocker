// lib/screens/enroll_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

enum EnrollStage { form, capture, uploading, done }

class EnrollScreen extends StatefulWidget {
  final String baseUrl; // e.g. http://192.168.70.14:8000
  final String userId; // prefill; editable on Step 1
  final String? siteId; // optional filter for lockers by site_id
  final int minShots; // minimum photos to capture before upload
  final int maxShots; // upper cap for captured photos

  const EnrollScreen({
    super.key,
    required this.baseUrl,
    required this.userId,
    this.siteId,
    this.minShots = 3,
    this.maxShots = 10,
  });

  static const route = '/enroll';

  @override
  State<EnrollScreen> createState() => _EnrollScreenState();
}

class _EnrollScreenState extends State<EnrollScreen> {
  // Stage
  EnrollStage _stage = EnrollStage.form;

  // -------- Step 1: form --------
  final _formKey = GlobalKey<FormState>();
  final _userIdCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _loadingLockers = true;
  String? _lockersError;
  List<int> _freeLockers = [];
  int? _selectedLockerId;

  // -------- Step 2: camera/capture --------
  List<CameraDescription> _cameras = [];
  CameraLensDirection _lens = CameraLensDirection.front;

  CameraController? _cam;
  bool _camOpened = false;
  Timer? _afNudgeTimer;
  bool _afLikelySupported = false;

  final List<XFile> _shots = [];
  bool _busy = false;
  String _status = 'Capture 3–5 photos: front, slight left, slight right.';
  String? _error;
  final List<String> _log = [];

  @override
  void initState() {
    super.initState();
    _userIdCtrl.text = widget.userId; // prefill (editable)
    _fetchFreeLockers();
  }

  @override
  void dispose() {
    _afNudgeTimer?.cancel();
    _teardownCamera();
    _userIdCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  // ───────────────────────────── Lockers ─────────────────────────────
  Future<void> _fetchFreeLockers() async {
    setState(() {
      _loadingLockers = true;
      _lockersError = null;
    });
    try {
      final r = await http.get(Uri.parse('${widget.baseUrl}/api/lockers/free'));
      if (r.statusCode != 200) {
        throw Exception('HTTP ${r.statusCode}: ${r.body}');
      }
      final body = jsonDecode(r.body);
      final list = _asList(body);

      final ids = <int>[];
      final siteFilter = widget.siteId?.trim();
      for (final it in list) {
        if (it is! Map) continue;
        final siteId = (it['site_id'] as String?);
        if (siteFilter == null ||
            siteFilter.isEmpty ||
            siteId == null ||
            siteId == siteFilter) {
          final raw = it['locker_id'] ?? it['id'];
          final id =
              raw is int ? raw : (raw is String ? int.tryParse(raw) : null);
          if (id != null) ids.add(id);
        }
      }
      ids.sort();

      setState(() {
        _freeLockers = ids;
        _selectedLockerId = ids.isNotEmpty ? ids.first : null;
      });
    } catch (e) {
      setState(() {
        _freeLockers = [];
        _selectedLockerId = null;
        _lockersError = 'Failed to load free lockers: $e';
      });
    } finally {
      if (mounted) setState(() => _loadingLockers = false);
    }
  }

  List _asList(dynamic x) {
    if (x is List) return x;
    if (x is Map) {
      for (final k in ['items', 'results', 'data', 'lockers']) {
        final v = x[k];
        if (v is List) return v;
      }
      return [x];
    }
    return const [];
  }

  // ───────────────────────────── Stage nav ─────────────────────────────
  Future<void> _goToCapture() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedLockerId == null) {
      _toast('Please select a free locker.');
      return;
    }
    setState(() {
      _shots.clear();
      _error = null;
      _status = 'Capture 3–5 photos: front, slight left, slight right.';
      _log.clear();
      _stage = EnrollStage.capture;
    });
    await _initCamera(); // open camera now
  }

  void _backToForm() {
    setState(() {
      _stage = EnrollStage.form;
    });
    _teardownCamera();
  }

  // ───────────────────────────── Camera ─────────────────────────────
  Future<void> _ensureCameraList() async {
    if (_cameras.isEmpty) {
      _cameras = await availableCameras();
    }
  }

  CameraDescription _pickCameraForLens(CameraLensDirection lens) {
    try {
      return _cameras.firstWhere((c) => c.lensDirection == lens);
    } catch (_) {
      // Fallback: any available
      if (_cameras.isNotEmpty) return _cameras.first;
      throw 'No camera found';
    }
  }

  Future<void> _initCamera() async {
    try {
      await _ensureCameraList();
      final selected = _pickCameraForLens(_lens);

      await _teardownCamera();
      _cam = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _cam!.initialize();
      _camOpened = true;

      try {
        await _cam!.setZoomLevel(1.0);
      } catch (_) {}

      await _startAFNudge();

      if (!mounted) return;
      setState(() {
        _status = _afLikelySupported
            ? 'Focusing… capture 3–5 photos.'
            : 'Preparing… capture 3–5 photos.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Camera error: $e';
      });
    }
  }

  Future<void> _toggleLens() async {
    if (_busy) return;
    await _ensureCameraList();
    final next = _lens == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    final hasNext = _cameras.any((c) => c.lensDirection == next);
    if (!hasNext) {
      _toast(next == CameraLensDirection.front
          ? 'No front camera available.'
          : 'No rear camera available.');
      return;
    }
    setState(() => _lens = next);
    await _initCamera();
  }

  Future<void> _teardownCamera() async {
    _afNudgeTimer?.cancel();
    _camOpened = false;
    final cam = _cam;
    _cam = null;
    try {
      await cam?.dispose();
    } catch (_) {}
  }

  Future<void> _startAFNudge() async {
    try {
      await _cam!.setFocusMode(FocusMode.auto);
      await _cam!.setExposureMode(ExposureMode.auto);
      await _cam!.setFocusPoint(const Offset(0.5, 0.5));
      await _cam!.setExposurePoint(const Offset(0.5, 0.5));
      _afLikelySupported = true;
    } catch (_) {
      _afLikelySupported = false; // many front cameras are fixed-focus
    }

    int ticks = 0;
    _afNudgeTimer?.cancel();
    _afNudgeTimer =
        Timer.periodic(const Duration(milliseconds: 300), (t) async {
      if (!mounted || !_camOpened || _cam == null) {
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
        } catch (_) {}
      }
      if (ticks >= 6) t.cancel(); // ~1.8s of nudging
    });
  }

  // ───────────────────────────── Capture/Upload ─────────────────────────────
  Future<void> _capture() async {
    if (!_camOpened || _cam == null) return;
    if (_shots.length >= widget.maxShots) {
      _toast('Max ${widget.maxShots} shots reached.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Capturing…';
    });
    try {
      _afNudgeTimer?.cancel();
      final x = await _cam!.takePicture();
      if (!mounted) return;
      setState(() {
        _shots.add(x);
        _status = 'Captured ${_shots.length}/${widget.maxShots}. Vary angles.';
      });
      await _startAFNudge();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Capture failed: $e';
        _status = 'Try again.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_shots.length >= widget.maxShots) {
      _toast('Max ${widget.maxShots} shots reached.');
      return;
    }
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (x == null) return;
      if (!mounted) return;
      setState(() {
        _shots.add(x);
        _status =
            'Added from gallery. Total ${_shots.length}/${widget.maxShots}.';
      });
    } catch (e) {
      _toast('Pick failed: $e');
    }
  }

  Future<void> _enrollAndAssign() async {
    if (_shots.length < widget.minShots) {
      _toast('Capture or pick at least ${widget.minShots} photos.');
      return;
    }
    final userId = _userIdCtrl.text.trim();
    if (userId.isEmpty) {
      _toast('User ID is required.');
      return;
    }
    final lockerId = _selectedLockerId!;
    final name = _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim();

    setState(() {
      _busy = true;
      _stage = EnrollStage.uploading;
      _log.clear();
      _error = null;
    });

    try {
      // 1) Create user if needed
      await _createUserIfNeeded(userId, name);

      // 2) Upload faces
      int uploaded = 0;
      for (int i = 0; i < _shots.length; i++) {
        final shot = _shots[i];
        final uri = Uri.parse('${widget.baseUrl}/api/faces');
        final req = http.MultipartRequest('POST', uri)
          ..fields['user_id'] = userId
          ..files.add(await http.MultipartFile.fromPath('image', shot.path));
        final resp = await req.send();
        final body = await resp.stream.bytesToString();

        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          uploaded++;
          _log.add('[$i] ✅ ${resp.statusCode} ${_short(body)}');
        } else {
          _log.add('[$i] ❌ ${resp.statusCode} ${_short(body)}');
        }
        setState(() {}); // update log live
      }

      // 3) Create assignment
      await _createAssignment(userId, lockerId);
      _log.add('✅ Assigned locker $lockerId to $userId.');

      // Done
      setState(() {
        _busy = false;
        _stage = EnrollStage.done;
      });
      _teardownCamera();
    } catch (e) {
      setState(() {
        _busy = false;
        _stage = EnrollStage.capture; // go back to capture on error
      });
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Enrollment failed'),
          content: Text(e.toString()),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK')),
          ],
        ),
      );
    }
  }

  Future<void> _createUserIfNeeded(String userId, String? name) async {
    final uri = Uri.parse('${widget.baseUrl}/api/users/');
    final body = <String, dynamic>{'user_id': userId};
    if (name != null && name.isNotEmpty) body['name'] = name;
    final r = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (r.statusCode == 201) return; // created
    if (r.statusCode == 409) return; // exists
    throw Exception('Create user failed: ${r.statusCode} ${r.body}');
  }

  Future<void> _createAssignment(String userId, int lockerId) async {
    final uri = Uri.parse('${widget.baseUrl}/api/assignments/');
    final r = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId, 'locker_id': lockerId}),
    );
    if (r.statusCode != 201) {
      throw Exception('Assignment failed: ${r.statusCode} ${r.body}');
    }
  }

  void _removeShot(int i) {
    setState(() {
      _shots.removeAt(i);
      _status = 'Captured ${_shots.length}/${widget.maxShots}.';
    });
  }

  String _short(String s) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ');
    return t.length > 160 ? '${t.substring(0, 160)}…' : t;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ───────────────────────────── UI Builders ─────────────────────────────
  Widget _buildFormStep() {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Step 1 of 2',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('User & Locker',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: cs.primary,
              )),
          const SizedBox(height: 18),
          Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _userIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'User ID',
                    hintText: 'e.g. U_0001',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'User ID is required'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Display name (optional)',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined, size: 22),
                    const SizedBox(width: 10),
                    const Text('Select a free locker',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: _loadingLockers ? null : _fetchFreeLockers,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_loadingLockers)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator()),
                    ),
                  ),
                if (_lockersError != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child:
                        Text(_lockersError!, style: TextStyle(color: cs.error)),
                  ),
                if (!_loadingLockers &&
                    _freeLockers.isEmpty &&
                    _lockersError == null)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('No free lockers available right now.'),
                  ),
                if (_freeLockers.isNotEmpty)
                  DropdownButtonFormField<int>(
                    value: _selectedLockerId != null &&
                            _freeLockers.contains(_selectedLockerId)
                        ? _selectedLockerId
                        : null,
                    items: _freeLockers
                        .map((id) => DropdownMenuItem(
                            value: id, child: Text('Locker $id')))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedLockerId = v),
                    decoration: const InputDecoration(
                      hintText: 'Choose a locker',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v == null ? 'Locker is required' : null,
                  ),
                const SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('Continue to Camera'),
                    onPressed: (_loadingLockers ||
                            _freeLockers.isEmpty ||
                            _selectedLockerId == null)
                        ? null
                        : _goToCapture,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureStep() {
    final preview = (_camOpened && _cam != null && _cam!.value.isInitialized)
        ? _buildNonDistortingPreview()
        : const Center(child: CircularProgressIndicator());

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Camera area
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: preview),

                  // top gradient + status
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: IgnorePointer(
                      child: Container(
                        height: 120,
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
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Row(
                      children: [
                        if (_error == null)
                          const Icon(Icons.photo_camera_front_outlined,
                              color: Colors.white)
                        else
                          const Icon(Icons.error_outline,
                              color: Colors.redAccent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error ?? _status,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              shadows: [
                                Shadow(blurRadius: 4, color: Colors.black)
                              ],
                            ),
                          ),
                        ),
                        if (_busy)
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

                  // Floating actions: switch cam & pick gallery
                  Positioned(
                    right: 12,
                    bottom: 130, // above the thumbnails strip
                    child: Column(
                      children: [
                        _MiniCircleButton(
                          tooltip: _lens == CameraLensDirection.front
                              ? 'Switch to rear camera'
                              : 'Switch to front camera',
                          icon: Icons.cameraswitch_rounded,
                          onTap: _busy ? null : _toggleLens,
                        ),
                        const SizedBox(height: 10),
                        _MiniCircleButton(
                          tooltip: 'Pick from gallery',
                          icon: Icons.photo_library_outlined,
                          onTap: _busy ? null : _pickFromGallery,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Thumbs
            Container(
              color: Colors.black,
              height: 110,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _shots.isEmpty
                  ? const Center(
                      child: Text(
                        'Capture or pick at least 3 clear face photos.',
                        style: TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemBuilder: (_, i) {
                        final f = _shots[i];
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.file(
                                File(f.path),
                                width: 96,
                                height: 96,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              right: 2,
                              top: 2,
                              child: InkWell(
                                onTap: () => _removeShot(i),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.all(2),
                                  child: const Icon(Icons.close,
                                      size: 16, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemCount: _shots.length,
                    ),
            ),

            // Controls
            Container(
              color: Colors.black,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _backToForm,
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('Back'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : _capture,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Capture'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white10,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy || _shots.length < widget.minShots
                          ? null
                          : _enrollAndAssign,
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: Text('Enroll (${_shots.length})'),
                    ),
                  ),
                ],
              ),
            ),

            // Log
            if (_log.isNotEmpty)
              Container(
                color: Colors.black,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                alignment: Alignment.centerLeft,
                child: Text(
                  _log.join('\n'),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadingStep() {
    // simple overlay over capture UI
    return Stack(
      children: [
        _buildCaptureStep(),
        const Positioned.fill(
          child: IgnorePointer(
            child: ColoredBox(
              color: Color(0x33000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDoneStep() {
    final locker = _selectedLockerId;
    final userId = _userIdCtrl.text.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, size: 72, color: Colors.green),
          const SizedBox(height: 12),
          const Text('All set!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'User $userId assigned to locker $locker.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  // Camera preview helper
  Widget _buildNonDistortingPreview() {
    if (!_camOpened || _cam == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final ar = _cam!.value.aspectRatio;
    final previewAR = isPortrait ? (1 / ar) : ar;
    return Center(
      child: AspectRatio(
        aspectRatio: previewAR,
        child: CameraPreview(_cam!),
      ),
    );
  }

  // ───────────────────────────── Scaffold ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    Widget body;
    switch (_stage) {
      case EnrollStage.form:
        body = _buildFormStep();
        break;
      case EnrollStage.capture:
        body = _buildCaptureStep();
        break;
      case EnrollStage.uploading:
        body = _buildUploadingStep();
        break;
      case EnrollStage.done:
        body = _buildDoneStep();
        break;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Enroll User'),
        centerTitle: true,
      ),
      body: body,
    );
  }
}

// Small round icon button used for overlay actions
class _MiniCircleButton extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback? onTap;

  const _MiniCircleButton({
    required this.icon,
    this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Tooltip(
          message: tooltip ?? '',
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}
