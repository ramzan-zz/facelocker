// lib/main.dart
import 'package:flutter/material.dart';

import 'config.dart';
import 'screens/home_screen.dart';
import 'screens/recognize_and_unlock.dart';
import 'screens/enroll_screen.dart'; // ← single enroll screen
import 'screens/user_management_screen.dart'; // <-- add this import

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FaceLockerApp());
}

class FaceLockerApp extends StatelessWidget {
  const FaceLockerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FaceLocker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F6FEB)),
      ),
      home: const HomeScreen(),
      routes: {
        // Unlock
        RecognizeAndUnlockScreen.route: (_) => RecognizeAndUnlockScreen(
              backendBase: kBackendBase,
              mqttHost: kMqttHost,
              mqttPort: kMqttPort,
              siteId: kSiteId,
              // mqttUsername: kMqttUsername,
              // mqttPassword: kMqttPassword,
            ),

        // Single Enroll screen (does form + capture)
        EnrollScreen.route: (_) => EnrollScreen(
              baseUrl: kBackendBase,
              userId: '', // prefill; editable on Step 1
              siteId: kSiteId, // optional: filter lockers by site
              minShots: 3,
              maxShots: 10,
            ),

        UserManagementScreen.route: (_) => UserManagementScreen(
              baseUrl: kBackendBase,
              siteId: kSiteId,
            ),

        // If/when you add the user management screen, uncomment:
        // UserManagementScreen.route: (_) => UserManagementScreen(
        //       baseUrl: kBackendBase,
        //       siteId: kSiteId,
        //     ),
      },
    );
  }
}
