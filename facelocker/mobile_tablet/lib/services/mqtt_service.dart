import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  final String host;
  final int port;
  final String siteId;
  late MqttServerClient _client;
  MqttService({required this.host, this.port = 1883, required this.siteId}) {
    _client =
        MqttServerClient(
            host,
            'tablet-${DateTime.now().millisecondsSinceEpoch}',
          )
          ..port = port
          ..logging(on: false)
          ..keepAlivePeriod = 20;
  }

  Future<void> connect({String? username, String? password}) async {
    _client.connectionMessage =
        MqttConnectMessage()
            .withClientIdentifier(_client.clientIdentifier!)
            .startClean();
    await _client.connect(username, password);
  }

  void publishUnlock({
    required String userId,
    required int lockerId,
    int durationMs = 1200,
    double? confidence,
    double? liveness,
  }) {
    final topic = 'sites/$siteId/locker/cmd';
    final payload = jsonEncode({
      'request_id': '${DateTime.now().millisecondsSinceEpoch}-$userId',
      'user_id': userId,
      'locker_id': lockerId,
      'action': 'unlock',
      'duration_ms': durationMs,
      'confidence': confidence,
      'liveness': liveness,
      'source': _client.clientIdentifier,
    });
    final builder = MqttClientPayloadBuilder();
    builder.addUTF8String(payload);
    _client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }
}
