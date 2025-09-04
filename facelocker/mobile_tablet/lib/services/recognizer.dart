import 'dart:math';

class Recognizer {
  // TODO: load TFLite model and provide embedding() + cosine search
  Future<(String, double, double)?> identifyFromCameraFrame(
    /* CameraImage frame */
  ) async {
    // TEMP: return a fake user for prototyping
    await Future.delayed(const Duration(milliseconds: 200));
    final conf = 0.88 + Random().nextDouble() * 0.04;
    final live = 0.90 + Random().nextDouble() * 0.05;
    return ('U_0001', conf.clamp(0.0, 0.99), live.clamp(0.0, 0.99));
  }
}
