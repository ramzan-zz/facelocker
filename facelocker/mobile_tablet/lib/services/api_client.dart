import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import '../models/locker.dart';

class ApiClient {
  final String baseUrl; // e.g. http://<server>:8000
  ApiClient(this.baseUrl);

  Future<(List<User>, List<Locker>, Map<String, int>)> sync() async {
    final u = await http.get(Uri.parse('$baseUrl/api/users/'));
    final l = await http.get(Uri.parse('$baseUrl/api/lockers/'));
    final a = await http.get(Uri.parse('$baseUrl/api/assignments/'));

    final users =
        (jsonDecode(u.body) as List)
            .map((e) => User(e['id'], e['name']))
            .toList();
    final lockers =
        (jsonDecode(l.body) as List)
            .map((e) => Locker(e['id'], e['channel']))
            .toList();
    final assign = <String, int>{};
    for (final row in (jsonDecode(a.body) as List)) {
      assign[row['user_id']] = row['locker_id'];
    }
    return (users, lockers, assign);
  }
}
