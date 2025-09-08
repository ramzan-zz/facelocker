import 'package:flutter/material.dart';
import '../security/admin_gate.dart';
import '../screens/settings_screen.dart';

/// AppBar action that toggles admin mode with a lock icon.
/// - Tap to enable/disable admin mode (asks for PIN if locked).
/// - Long-press to open a quick menu (Change PIN / Lock now).
class AdminLockAction extends StatelessWidget {
  const AdminLockAction(
      {super.key, this.rememberFor = const Duration(minutes: 10)});
  final Duration rememberFor;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AdminGate.I,
      builder: (context, _) {
        final active = AdminGate.I.isActive;
        return IconButton(
          tooltip: active ? 'Disable admin mode' : 'Enable admin mode',
          icon: Icon(active ? Icons.lock_open : Icons.lock),
          onPressed: () async {
            if (active) {
              await AdminGate.I.lock();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Admin mode disabled')),
                );
              }
            } else {
              final ok =
                  await AdminGate.I.ensure(context, rememberFor: rememberFor);
              if (ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          'Admin mode enabled (${rememberFor.inMinutes} min)')),
                );
              }
            }
          },
          onLongPress: () async {
            final active = AdminGate.I.isActive;
            final selection = await showMenu<String>(
              context: context,
              position: const RelativeRect.fromLTRB(1000, 80, 8, 0),
              items: [
                if (active)
                  const PopupMenuItem(value: 'lock', child: Text('Lock now')),
                const PopupMenuItem(value: 'change', child: Text('Change PIN')),
              ],
            );
            if (!context.mounted) return;
            switch (selection) {
              case 'lock':
                await AdminGate.I.lock();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Admin mode disabled')),
                );
                break;
              case 'change':
                Navigator.of(context).pushNamed(SettingsScreen.route);
                break;
            }
          },
        );
      },
    );
  }
}

// NOTE: import your real SettingsScreen here or adjust route name.
