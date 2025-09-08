// lib/main.dart
import 'package:flutter/material.dart';

import 'security/admin_gate.dart';
import 'widgets/powered_by_footer.dart';

import 'config.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/recognize_and_unlock.dart';
import 'screens/enroll_screen.dart';
import 'screens/user_management_screen.dart';
import 'shared/footer_state.dart'; // <-- add at top of file

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AdminGate.I.init();
  runApp(const FaceLockerApp());
}

class FaceLockerApp extends StatelessWidget {
  const FaceLockerApp({super.key});

  // ✅ Global navigator key gives us a Navigator-descendant context anywhere.
  static final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  static const double _footerHeight = 36.0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FaceLocker',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navKey, // <-- important
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F6FEB)),
      ),
      home: const HomeScreen(),
      routes: {
        // Settings
        SettingsScreen.route: (_) => const SettingsScreen(),

        // Unlock
        RecognizeAndUnlockScreen.route: (_) => RecognizeAndUnlockScreen(
              backendBase: kBackendBase,
              mqttHost: kMqttHost,
              mqttPort: kMqttPort,
              siteId: kSiteId,
              // mqttUsername: kMqttUsername,
              // mqttPassword: kMqttPassword,
            ),

        // Enroll (single-screen flow)
        EnrollScreen.route: (_) => EnrollScreen(
              baseUrl: kBackendBase,
              userId: '', // prefill; editable on Step 1
              siteId: kSiteId, // optional site filter
              minShots: 3,
              maxShots: 10,
            ),

        // User management
        UserManagementScreen.route: (_) => UserManagementScreen(
              baseUrl: kBackendBase,
              siteId: kSiteId,
            ),

        // Back-compat alias if something calls '/users'
        '/users': (_) => UserManagementScreen(
              baseUrl: kBackendBase,
              siteId: kSiteId,
            ),
      },

      // Global footer injection with Navigator-safe onTap
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();

        // Add bottom padding so content doesn’t sit under the footer.
        final media = MediaQuery.of(context);
        final adjustedChild = MediaQuery(
          data: media.copyWith(
            padding: media.padding.copyWith(
              bottom: media.padding.bottom + _footerHeight,
            ),
          ),
          child: child,
        );

        return Stack(
          children: [
            Positioned.fill(child: adjustedChild),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ValueListenableBuilder<bool>(
                valueListenable: footerSheetOpen,
                builder: (context, isOpen, _) {
                  return IgnorePointer(
                    ignoring: isOpen, // let taps hit the sheet/scrim
                    child: AnimatedOpacity(
                      opacity:
                          isOpen ? 0.0 : 1.0, // hide footer while sheet is open
                      duration: const Duration(milliseconds: 180),
                      child: PoweredByFooter(
                        height: _footerHeight,
                        onTap: () {
                          final navCtx = _navKey.currentContext;
                          if (navCtx == null) return;

                          if (footerSheetOpen.value) {
                            // Sheet is open → close it
                            Navigator.of(navCtx).maybePop();
                          } else {
                            // Sheet is closed → open it
                            _showAbout(navCtx);
                          }
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

void _showAbout(BuildContext ctx) {
  final scheme = Theme.of(ctx).colorScheme;
  footerSheetOpen.value = true; // mark open

  showModalBottomSheet(
    context: ctx,
    showDragHandle: true,
    backgroundColor: scheme.surface,
    builder: (bctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium_rounded,
              color: scheme.primary, size: 28),
          const SizedBox(height: 8),
          Text('FaceLocker',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface)),
          const SizedBox(height: 4),
          Text('Powered by Syncronose',
              style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          Text(
            'Secure, fast, and flexible locker access using on-device capture, cloud recognition, and MQTT control.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('Close'),
            onPressed: () => Navigator.of(bctx).maybePop(),
          ),
        ],
      ),
    ),
  ).whenComplete(() {
    // sheet closed → show footer again
    footerSheetOpen.value = false;
  });
}
