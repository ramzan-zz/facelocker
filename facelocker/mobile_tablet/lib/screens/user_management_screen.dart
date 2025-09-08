// lib/screens/user_management_screen.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class UserManagementScreen extends StatefulWidget {
  final String baseUrl; // e.g. http://192.168.70.14:8000
  final String? siteId; // optional: to filter free lockers by site

  const UserManagementScreen({
    super.key,
    required this.baseUrl,
    this.siteId,
  });

  static const route = '/users';

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserItem {
  final int id;
  final String userId;
  final String? name;
  final String? status;

  _UserItem({required this.id, required this.userId, this.name, this.status});

  factory _UserItem.fromJson(Map<String, dynamic> m) {
    return _UserItem(
      id: (m['id'] is int) ? m['id'] : int.tryParse('${m['id']}') ?? -1,
      userId: '${m['user_id']}',
      name: (m['name'] as String?)?.trim().isEmpty == true ? null : m['name'],
      status:
          (m['status'] as String?)?.trim().isEmpty == true ? null : m['status'],
    );
  }
}

class _FaceItem {
  final String faceId;
  final String? imageUrl;

  _FaceItem({required this.faceId, this.imageUrl});
}

class _UserExtras {
  int? currentLockerId;
  List<_FaceItem> faces = [];
  bool expanded = false;
  bool loading = false;
  String? error;
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  bool _loading = true;
  String? _error;
  List<_UserItem> _users = [];
  final Map<String, _UserExtras> _extras = {}; // keyed by userId

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
      _users = [];
      _extras.clear();
    });
    try {
      final r = await http.get(Uri.parse('${widget.baseUrl}/api/users/'));
      if (r.statusCode != 200) {
        throw Exception('GET /api/users failed: ${r.statusCode} ${r.body}');
      }
      final decoded = jsonDecode(r.body);
      final List list = decoded is List ? decoded : [decoded];
      final users = list
          .whereType<Map<String, dynamic>>()
          .map((m) => _UserItem.fromJson(m))
          .toList();

      setState(() {
        _users = users;
      });

      // Load per-user extras (locker + faces) lazily on expand to avoid N calls upfront
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ensureExtras(_UserItem u) async {
    final ex = _extras[u.userId] ?? _UserExtras();
    if (ex.loading) return;
    ex.loading = true;
    ex.error = null;
    setState(() => _extras[u.userId] = ex);

    try {
      // current assignment
      try {
        final rr = await http.get(Uri.parse(
            '${widget.baseUrl}/api/assignments/current?user_id=${Uri.encodeQueryComponent(u.userId)}'));
        if (rr.statusCode == 200) {
          final m = jsonDecode(rr.body);
          final raw = m['locker_id'];
          ex.currentLockerId = raw is int ? raw : int.tryParse('$raw');
        } else {
          ex.currentLockerId = null;
        }
      } catch (_) {
        ex.currentLockerId = null;
      }

      // faces
      try {
        final rf = await http.get(Uri.parse(
            '${widget.baseUrl}/api/faces?user_id=${Uri.encodeQueryComponent(u.userId)}'));
        if (rf.statusCode == 200) {
          final data = jsonDecode(rf.body);
          final List items = (data is List)
              ? data
              : (data['items'] ?? data['results'] ?? data['data'] ?? []);
          ex.faces = items.whereType<Map>().map<_FaceItem>((m) {
            final fid = '${m['face_id'] ?? m['id'] ?? ''}';
            String? url = m['image_url'] as String?;
            // Fallback if image_url not present
            if ((url == null || url.isEmpty) && fid.isNotEmpty) {
              url = '/static/faces/${u.userId}/$fid.jpg';
            }
            return _FaceItem(faceId: fid, imageUrl: url);
          }).toList();
        } else {
          ex.faces = [];
        }
      } catch (_) {
        ex.faces = [];
      }
    } catch (e) {
      ex.error = e.toString();
    } finally {
      ex.loading = false;
      setState(() => _extras[u.userId] = ex);
    }
  }

  Future<void> _changeLocker(_UserItem u) async {
    // Load free lockers
    List<int> free = [];
    String? err;
    try {
      final r = await http.get(Uri.parse('${widget.baseUrl}/api/lockers/free'));
      if (r.statusCode != 200) {
        throw Exception('HTTP ${r.statusCode}: ${r.body}');
      }
      final decoded = jsonDecode(r.body);
      final List list = decoded is List
          ? decoded
          : (decoded['items'] ?? decoded['results'] ?? decoded['data'] ?? []);
      final siteFilter = widget.siteId?.trim();
      for (final it in list.whereType<Map>()) {
        final sid = it['site_id'] as String?;
        if (siteFilter == null ||
            siteFilter.isEmpty ||
            sid == null ||
            sid == siteFilter) {
          final raw = it['locker_id'] ?? it['id'];
          final id = raw is int ? raw : int.tryParse('$raw');
          if (id != null) free.add(id);
        }
      }
      free.sort();
    } catch (e) {
      err = e.toString();
    }

    if (!mounted) return;
    if (err != null) {
      _snack('Failed to load free lockers: $err');
      return;
    }
    if (free.isEmpty) {
      _snack('No free lockers right now.');
      return;
    }

    int? picked = free.first;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Assign locker to ${u.userId}'),
        content: DropdownButtonFormField<int>(
          value: picked,
          items: free
              .map((id) =>
                  DropdownMenuItem(value: id, child: Text('Locker $id')))
              .toList(),
          onChanged: (v) => picked = v,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (picked == null) return;
              final ok = await _postAssignment(u.userId, picked!);
              if (ok) {
                _snack('Assigned locker $picked to ${u.userId}.');
                // refresh extras (current locker)
                final ex = _extras[u.userId];
                if (ex != null) {
                  ex.currentLockerId = picked;
                  setState(() {});
                }
              }
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Assign'),
          ),
        ],
      ),
    );
  }

  Future<bool> _postAssignment(String userId, int lockerId) async {
    try {
      final r = await http.post(
        Uri.parse('${widget.baseUrl}/api/assignments/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId, 'locker_id': lockerId}),
      );
      if (r.statusCode == 201 || (r.statusCode >= 200 && r.statusCode < 300)) {
        return true;
      }
      _snack('Assignment failed: ${r.statusCode} ${r.body}');
      return false;
    } catch (e) {
      _snack('Assignment error: $e');
      return false;
    }
  }

  Future<void> _addFace(_UserItem u) async {
    XFile? x;
    final pick = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Capture with camera'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Pick from gallery'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
          ],
        ),
      ),
    );
    if (pick == null) return;

    try {
      if (pick == 'camera') {
        x = await ImagePicker().pickImage(
            source: ImageSource.camera,
            preferredCameraDevice: CameraDevice.front);
      } else {
        x = await ImagePicker().pickImage(source: ImageSource.gallery);
      }
      if (x == null) return;

      final uri = Uri.parse('${widget.baseUrl}/api/faces');
      final req = http.MultipartRequest('POST', uri)
        ..fields['user_id'] = u.userId
        ..files.add(await http.MultipartFile.fromPath('image', x.path));
      final resp = await req.send();
      final body = await resp.stream.bytesToString();

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        _snack('Face added.');
        // update faces list
        await _ensureExtras(u);
      } else {
        _snack('Add face failed: ${resp.statusCode} $body');
      }
    } catch (e) {
      _snack('Add face error: $e');
    }
  }

  Future<void> _deleteFace(_UserItem u, _FaceItem f) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete face image?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final r = await http.delete(Uri.parse(
          '${widget.baseUrl}/api/faces/${Uri.encodeComponent(f.faceId)}'));
      if (r.statusCode >= 200 && r.statusCode < 300) {
        _snack('Face deleted.');
        // remove from UI
        final ex = _extras[u.userId];
        if (ex != null) {
          ex.faces.removeWhere((ff) => ff.faceId == f.faceId);
          setState(() {});
        }
      } else {
        _snack('Delete failed: ${r.statusCode} ${r.body}');
      }
    } catch (e) {
      _snack('Delete error: $e');
    }
  }

  Future<void> _toggleDisable(_UserItem u) async {
    final target =
        (u.status?.toLowerCase() == 'disabled') ? 'active' : 'disabled';
    final ok = await _patchUserStatus(u, target);
    if (ok) {
      _snack('User ${u.userId} set to $target.');
      // Update local state
      final idx = _users.indexWhere((x) => x.userId == u.userId);
      if (idx >= 0) {
        final nu =
            _UserItem(id: u.id, userId: u.userId, name: u.name, status: target);
        setState(() => _users[idx] = nu);
      }
    }
  }

  /// Tries PATCH /api/users/{id} with {"status": "..."}.
  /// If not implemented on backend, shows a snackbar and returns false.
  Future<bool> _patchUserStatus(_UserItem u, String status) async {
    try {
      final r = await http.patch(
        Uri.parse('${widget.baseUrl}/api/users/${u.id}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': status}),
      );
      if (r.statusCode >= 200 && r.statusCode < 300) return true;
      if (r.statusCode == 404 || r.statusCode == 405) {
        _snack('PATCH /api/users/{id} not available on backend.');
        return false;
      }
      _snack('Status update failed: ${r.statusCode} ${r.body}');
      return false;
    } catch (e) {
      _snack('Status update error: $e');
      return false;
    }
  }

  Future<void> _deleteUser(_UserItem u) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete ${u.userId}?'),
        content: const Text(
            'All of this user\'s data will be removed (faces, assignments, etc.).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final r =
          await http.delete(Uri.parse('${widget.baseUrl}/api/users/${u.id}'));
      if (r.statusCode >= 200 && r.statusCode < 300) {
        _snack('User deleted.');
        setState(() {
          _users.removeWhere((x) => x.userId == u.userId);
          _extras.remove(u.userId);
        });
      } else if (r.statusCode == 404 || r.statusCode == 405) {
        _snack('DELETE /api/users/{id} not available on backend.');
      } else {
        _snack('Delete failed: ${r.statusCode} ${r.body}');
      }
    } catch (e) {
      _snack('Delete error: $e');
    }
  }

  // ───────────── UI helpers ─────────────
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _userTile(_UserItem u) {
    final ex = _extras[u.userId];
    final status = (u.status ?? 'active').toLowerCase();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: ex?.expanded ?? false,
        onExpansionChanged: (v) async {
          final cur = _extras[u.userId] ?? _UserExtras();
          cur.expanded = v;
          _extras[u.userId] = cur;
          setState(() {});
          if (v) await _ensureExtras(u);
        },
        title: Row(
          children: [
            Text(u.userId, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            if (u.name != null && u.name!.isNotEmpty)
              Flexible(
                child: Text('· ${u.name!}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.black.withOpacity(0.6))),
              ),
          ],
        ),
        subtitle: Row(
          children: [
            Chip(
              label: Text(status),
              visualDensity: VisualDensity.compact,
              backgroundColor: status == 'disabled'
                  ? Colors.red.shade50
                  : Colors.green.shade50,
              side: BorderSide(
                  color: status == 'disabled'
                      ? Colors.red.shade200
                      : Colors.green.shade200),
            ),
            const SizedBox(width: 8),
            if (ex?.currentLockerId != null)
              Text('Locker ${ex!.currentLockerId}',
                  style: TextStyle(color: Colors.black.withOpacity(0.7))),
          ],
        ),
        children: [
          if (ex?.loading == true)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                    width: 22, height: 22, child: CircularProgressIndicator()),
              ),
            ),
          if (ex?.error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(ex!.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),

          // Faces strip
          if (ex != null && ex.faces.isNotEmpty)
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                itemCount: ex.faces.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final f = ex.faces[i];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: f.imageUrl != null
                            ? Image.network(
                                _absoluteUrl(f.imageUrl!),
                                width: 96,
                                height: 96,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _facePlaceholder(),
                              )
                            : _facePlaceholder(),
                      ),
                      Positioned(
                        right: 2,
                        top: 2,
                        child: InkWell(
                          onTap: () => _deleteFace(u, f),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.all(2),
                            child: const Icon(Icons.delete_outline,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

          // Actions row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () => _changeLocker(u),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Change locker'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _addFace(u),
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Add face'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _toggleDisable(u),
                  icon: Icon(
                      status == 'disabled' ? Icons.lock_open : Icons.block),
                  label: Text(
                      status == 'disabled' ? 'Enable user' : 'Disable user'),
                ),
                TextButton.icon(
                  onPressed: () => _deleteUser(u),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete user'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _facePlaceholder() => Container(
        width: 96,
        height: 96,
        color: Colors.grey.shade300,
        alignment: Alignment.center,
        child: const Icon(Icons.person, color: Colors.white70, size: 32),
      );

  String _absoluteUrl(String url) {
    // Accept absolute or backend-relative
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final base = widget.baseUrl.replaceAll(RegExp(r'\/+$'), '');
    final rel = url.startsWith('/') ? url : '/$url';
    return '$base$rel';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(_error!, style: TextStyle(color: cs.error)),
                  ),
                )
              : _users.isEmpty
                  ? const Center(child: Text('No users yet.'))
                  : RefreshIndicator(
                      onRefresh: _loadAll,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                        itemCount: _users.length,
                        itemBuilder: (_, i) => _userTile(_users[i]),
                      ),
                    ),
    );
  }
}
