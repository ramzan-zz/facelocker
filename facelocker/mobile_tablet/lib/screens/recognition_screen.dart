import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../services/mqtt_service.dart';
import '../services/recognizer.dart';

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
              Text(
                'FaceLocker',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed:
                    busy
                        ? null
                        : () async {
                          setState(() => busy = true);
                          final result = await rec.identifyFromCameraFrame();
                          if (result != null) {
                            final (userId, conf, live) = result;
                            final lockerId = app.assignment[userId];
                            if (lockerId != null) {
                              final mqtt = MqttService(
                                host: '10.0.2.2',
                                siteId: app.siteId,
                              ); // change IP
                              await mqtt.connect();
                              mqtt.publishUnlock(
                                userId: userId,
                                lockerId: lockerId,
                                durationMs: 1200,
                                confidence: conf,
                                liveness: live,
                              );
                              setState(
                                () =>
                                    lastMsg =
                                        'Welcome $userId → Locker $lockerId unlocked',
                              );
                            } else {
                              setState(
                                () =>
                                    lastMsg = 'No locker assigned for $userId',
                              );
                            }
                          } else {
                            setState(() => lastMsg = 'No match');
                          }
                          setState(() => busy = false);
                        },
                child: Text(busy ? 'Scanning…' : 'Scan & Unlock'),
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
