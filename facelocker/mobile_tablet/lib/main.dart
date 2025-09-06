// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config.dart';
import 'screens/recognize_and_unlock.dart';

// OPTIONAL: if you have AppState hydration elsewhere, you can add it back.
// For now, we keep main lean and go straight to the screen.
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FaceLocker',
      theme: ThemeData(useMaterial3: true),
      home: const _Home(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class _Home extends StatelessWidget {
  const _Home({super.key});
  @override
  Widget build(BuildContext context) {
    return RecognizeAndUnlockScreen(
      backendBase: kBackendBase,
      mqttHost: kMqttHost,
      mqttPort: kMqttPort,
      siteId: kSiteId,
      // mqttUsername: 'tablet-site-001', // fill if broker has auth
      // mqttPassword: 'STRONG_PASS',
    );
  }
}
