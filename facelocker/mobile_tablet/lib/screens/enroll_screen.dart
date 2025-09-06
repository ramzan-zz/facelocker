import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

class EnrollScreen extends StatefulWidget {
  final String baseUrl; // e.g. http://10.0.0.5:8000
  final String userId; // e.g. U_0001
  const EnrollScreen({super.key, required this.baseUrl, required this.userId});
  @override
  State<EnrollScreen> createState() => _EnrollScreenState();
}

class _EnrollScreenState extends State<EnrollScreen> {
  XFile? _file;
  bool _busy = false;
  String? _result;

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(
        source: ImageSource.camera, preferredCameraDevice: CameraDevice.front);
    if (x != null) setState(() => _file = x);
  }

  Future<void> _upload() async {
    if (_file == null) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    final uri = Uri.parse('${widget.baseUrl}/api/faces');
    final req = http.MultipartRequest('POST', uri)
      ..fields['user_id'] = widget.userId
      ..files.add(await http.MultipartFile.fromPath('image', _file!.path));
    final resp = await req.send();
    final body = await resp.stream.bytesToString();
    setState(() {
      _busy = false;
      _result = '${resp.statusCode}: $body';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enroll Face')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_file != null) Expanded(child: Image.file(File(_file!.path))),
            if (_file == null)
              const Expanded(child: Center(child: Text('Pick a selfie'))),
            const SizedBox(height: 12),
            if (_busy) const CircularProgressIndicator(),
            if (_result != null) Text(_result!),
            Row(
              children: [
                ElevatedButton(onPressed: _pick, child: const Text('Capture')),
                const SizedBox(width: 12),
                ElevatedButton(onPressed: _upload, child: const Text('Enroll')),
              ],
            )
          ],
        ),
      ),
    );
  }
}
