import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const AdminApp());

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: AdminHome());
  }
}

class AdminHome extends StatefulWidget {
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  final base = 'http://localhost:8000';
  List users = [], lockers = [], assignments = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    users = jsonDecode((await http.get(Uri.parse('$base/api/users/'))).body);
    lockers = jsonDecode(
      (await http.get(Uri.parse('$base/api/lockers/'))).body,
    );
    assignments = jsonDecode(
      (await http.get(Uri.parse('$base/api/assignments/'))).body,
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FaceLocker Admin')),
      body: Row(
        children: [
          Expanded(child: _table('Users', users, ['id', 'name', 'status'])),
          Expanded(child: _table('Lockers', lockers, ['id', 'channel'])),
          Expanded(
            child: _table('Assignments', assignments, ['user_id', 'locker_id']),
          ),
        ],
      ),
    );
  }

  Widget _table(String title, List data, List<String> cols) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: data.length,
            itemBuilder: (_, i) {
              final row = data[i] as Map<String, dynamic>;
              return ListTile(
                title: Text(cols.map((k) => '${row[k]}').join(' | ')),
              );
            },
          ),
        ),
      ],
    );
  }
}
