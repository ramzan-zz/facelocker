// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import '../config.dart'; // <- for kBackendBase
import 'enroll_screen.dart'; // <- the screen we just built

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('FaceLocker'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 700;
            final crossAxisCount = isWide ? 3 : 2;

            return GridView.count(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              children: [
                _HomeCard(
                  icon: Icons.lock_open_rounded,
                  title: 'Unlock',
                  subtitle: 'Recognize & open assigned locker',
                  color: color.primaryContainer,
                  iconColor: color.onPrimaryContainer,
                  onTap: () => Navigator.pushNamed(context, '/unlock'),
                ),
                _HomeCard(
                  icon: Icons.person_add_alt_1_rounded,
                  title: 'Enroll',
                  subtitle: 'Add a new user face profile',
                  color: color.secondaryContainer,
                  iconColor: color.onSecondaryContainer,
                  onTap: () => _openEnroll(context),
                ),
                // Add more cards later (Assignments, Events, Settings, etc.)
                // inside GridView.count(children: [...])
                _HomeCard(
                  icon: Icons.group_outlined,
                  title: 'Users',
                  subtitle: 'Assign lockers, faces & status',
                  color: color.tertiaryContainer,
                  iconColor: color.onTertiaryContainer,
                  onTap: () => Navigator.pushNamed(context, '/users'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _openEnroll(BuildContext context) async {
    final userId = await _promptUserId(context);
    if (userId == null || userId.trim().isEmpty) return;

    // Navigate directly (no need to add a named route)
    // Pass your backend base URL and the chosen userId.
    // Ensure kBackendBase is defined in config.dart (same one used by unlock).
    // Example: const kBackendBase = 'http://192.168.70.14:8000';
    // ignore: use_build_context_synchronously
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EnrollScreen(
          baseUrl: kBackendBase,
          userId: userId.trim(),
        ),
      ),
    );
  }

  Future<String?> _promptUserId(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        String current = '';
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: const Text('Enroll user'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Enter the User ID to enroll (e.g. U_0001).',
                    style: TextStyle(fontSize: 13.5),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.badge_outlined),
                      hintText: 'U_0001',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => current = v),
                    onSubmitted: (v) {
                      final trimmed = v.trim();
                      if (trimmed.isNotEmpty) Navigator.pop(ctx, trimmed);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: (current.trim().isEmpty)
                      ? null
                      : () => Navigator.pop(ctx, current.trim()),
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _HomeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? color;
  final Color? iconColor;

  const _HomeCard({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.color,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: color ?? Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 44, color: iconColor ?? textColor),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: iconColor ?? textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: (iconColor ?? textColor).withOpacity(0.8),
                    fontSize: 12.5,
                    height: 1.2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
