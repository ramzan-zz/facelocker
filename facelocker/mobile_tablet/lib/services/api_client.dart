// lib/services/api_client.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class User {
  final int id;
  final String userId;
  final String? name;
  final String? status;
  User({required this.id, required this.userId, this.name, this.status});
  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as int,
        userId: j['user_id'] as String,
        name: j['name'] as String?,
        status: j['status'] as String?,
      );
}

class Locker {
  final int id;
  final int lockerId;
  final String? siteId;
  final int channel;
  final String? notes;
  Locker(
      {required this.id,
      required this.lockerId,
      this.siteId,
      required this.channel,
      this.notes});
  factory Locker.fromJson(Map<String, dynamic> j) => Locker(
        id: j['id'] as int,
        lockerId: j['locker_id'] as int,
        siteId: j['site_id'] as String?,
        channel: j['channel'] as int,
        notes: j['notes'] as String?,
      );
}

class Assignment {
  final String userId;
  final int lockerId;
  Assignment({required this.userId, required this.lockerId});
  factory Assignment.fromJson(Map<String, dynamic> j) => Assignment(
        userId: j['user_id'] as String,
        lockerId: j['locker_id'] as int,
      );
}

class ApiClient {
  final String base;
  final http.Client _c = http.Client();
  ApiClient(this.base);

  Future<(List<User>, List<Locker>, List<Assignment>)> sync() async {
    final u = await _c.get(Uri.parse('$base/api/users/'));
    final l = await _c.get(Uri.parse('$base/api/lockers/'));
    final a = await _c.get(Uri.parse('$base/api/assignments/'));
    if (u.statusCode != 200 || l.statusCode != 200 || a.statusCode != 200) {
      throw Exception(
          'Sync failed: ${u.statusCode}/${l.statusCode}/${a.statusCode}');
    }
    final users =
        (jsonDecode(u.body) as List).map((e) => User.fromJson(e)).toList();
    final lockers =
        (jsonDecode(l.body) as List).map((e) => Locker.fromJson(e)).toList();
    final assigns = (jsonDecode(a.body) as List)
        .map((e) => Assignment.fromJson(e))
        .toList();
    return (users, lockers, assigns);
  }
}
