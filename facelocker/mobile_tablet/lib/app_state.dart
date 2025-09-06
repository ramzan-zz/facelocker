// lib/app_state.dart
import 'package:flutter/foundation.dart';
import 'services/api_client.dart';

class AppState extends ChangeNotifier {
  List<User> users = [];
  final Map<int, Locker> lockersById = {}; // lockerId -> Locker
  final Map<String, int> assignment = {}; // userId  -> lockerId

  void hydrate(
      {required List<User> u,
      required List<Locker> l,
      required List<Assignment> a}) {
    users = u;
    lockersById
      ..clear()
      ..addEntries(l.map((lk) => MapEntry(lk.lockerId, lk)));
    assignment
      ..clear()
      ..addEntries(a.map((as) => MapEntry(as.userId, as.lockerId)));
    notifyListeners();
  }

  String debugSummary() =>
      'users=${users.length}, lockers=${lockersById.length}, assigns=${assignment.length}';
}
