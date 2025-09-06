import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../services/mqtt_service.dart';
import '../services/recognizer.dart';
import '../config.dart';

class RecognitionScreen extends StatefulWidget {
  const RecognitionScreen({super.key});
  @override
  State<RecognitionScreen> createState() => _RecognitionScreenState();
}

class _RecognitionScreenState extends State<RecognitionScreen> {
  final rec = Recognizer();
  bool busy = false;
  String? lastMsg;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'FaceLocker',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() => busy = true);
                        final result = await rec.identifyFromCameraFrame();
                        if (!mounted) return;

                        if (result != null) {
                          final (userId, conf, live) = result;
                          final lockerId = app.assignment[userId];
                          if (lockerId != null) {
                            try {
                              final mqtt = MqttService(
                                host: kMqttHost,
                                port: kMqttPort,
                                siteId: kSiteId,
                              );
                              await mqtt.connect();
                              if (!mounted) return;

                              mqtt.publishUnlock(
                                userId: userId,
                                lockerId: lockerId,
                                durationMs: 1200,
                                confidence: conf,
                                liveness: live,
                              );

                              setState(() => lastMsg =
                                  'Welcome $userId -> Locker $lockerId unlocked');
                            } catch (e) {
                              if (!mounted) return;
                              setState(
                                  () => lastMsg = 'Failed to send unlock: $e');
                            }
                          } else {
                            setState(() =>
                                lastMsg = 'No locker assigned for $userId');
                          }
                        } else {
                          setState(() => lastMsg = 'No match');
                        }
                        if (!mounted) return;
                        setState(() => busy = false);
                      },
                child: Text(busy ? 'Scanning...' : 'Scan & Unlock'),
              ),
              if (lastMsg != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    lastMsg!,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
