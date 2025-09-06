import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

class RecognizeTestScreen extends StatefulWidget {
  final String baseUrl; // e.g. http://10.0.0.5:8000
  const RecognizeTestScreen({super.key, required this.baseUrl});
  @override
  State<RecognizeTestScreen> createState() => _RecognizeTestScreenState();
}

class _RecognizeTestScreenState extends State<RecognizeTestScreen> {
  XFile? _file;
  bool _busy = false;
  String? _result;

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(
        source: ImageSource.camera, preferredCameraDevice: CameraDevice.front);
    if (x != null) setState(() => _file = x);
  }

  Future<void> _send() async {
    if (_file == null) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    final uri = Uri.parse('${widget.baseUrl}/api/recognize');
    final req = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('image', _file!.path));
    final resp = await req.send();
    final body = await resp.stream.bytesToString();
    setState(() {
      _busy = false;
      _result = body;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recognition Test')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_file != null) Expanded(child: Image.file(File(_file!.path))),
            if (_file == null)
              const Expanded(
                  child: Center(child: Text('Capture a test frame'))),
            const SizedBox(height: 12),
            if (_busy) const CircularProgressIndicator(),
            if (_result != null)
              Expanded(child: SingleChildScrollView(child: Text(_result!))),
            Row(
              children: [
                ElevatedButton(onPressed: _pick, child: const Text('Capture')),
                const SizedBox(width: 12),
                ElevatedButton(
                    onPressed: _send, child: const Text('Recognize')),
              ],
            )
          ],
        ),
      ),
    );
  }
}
