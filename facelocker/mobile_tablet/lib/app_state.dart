import 'package:flutter/foundation.dart';
import 'models/user.dart';
import 'models/locker.dart';

class AppState extends ChangeNotifier {
  String siteId = 'site-001';
  Map<String, User> users = {};
  Map<int, Locker> lockers = {};
  Map<String, int> assignment = {}; // userId -> lockerId

  void hydrate({
    required List<User> u,
    required List<Locker> l,
    required Map<String, int> a,
  }) {
    users = {for (final x in u) x.id: x};
    lockers = {for (final x in l) x.id: x};
    assignment = a;
    notifyListeners();
  }
}
