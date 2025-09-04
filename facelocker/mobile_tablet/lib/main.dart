import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'services/api_client.dart';
import 'screens/recognition_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = AppState();
  // bootstrap with backend sync
  final api = ApiClient('http://10.0.2.2:8000'); // change to your backend IP
  final (users, lockers, assign) = await api.sync();
  app.hydrate(u: users, l: lockers, a: assign);
  runApp(ChangeNotifierProvider(create: (_) => app, child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'FaceLocker', home: const RecognitionScreen());
  }
}
