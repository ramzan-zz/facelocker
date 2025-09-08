import 'package:facelocker_tablet/widgets/admin_lock_action.dart';
import 'package:flutter/material.dart';
import '../security/admin_gate.dart';

class SettingsScreen extends StatefulWidget {
  static const route = '/settings';
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _newPin = TextEditingController();
  final _confirm = TextEditingController();
  bool _changing = false;

  @override
  void initState() {
    super.initState();
    // Route-level admin gate
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ok = await AdminGate.I.ensure(context);
      if (!ok && mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _current.dispose();
    _newPin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = AdminGate.I.isActive;
    final until = AdminGate.I.validUntil;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: const [AdminLockAction()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(active ? Icons.lock_open : Icons.lock),
              title: Text(
                  active ? 'Admin mode is ENABLED' : 'Admin mode is DISABLED'),
              subtitle: Text(active
                  ? (until != null
                      ? 'Until: ${until.toLocal()}'
                      : 'Session active')
                  : 'Tap the lock icon to enable'),
              trailing: active
                  ? TextButton(
                      onPressed: () async {
                        await AdminGate.I.lock();
                        if (mounted) setState(() {});
                      },
                      child: const Text('Lock now'),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),

          // Change PIN
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Change admin PIN',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _current,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      decoration:
                          const InputDecoration(labelText: 'Current PIN'),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _newPin,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 6,
                      decoration: const InputDecoration(
                          labelText: 'New PIN', counterText: ''),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        if (v.length < 4) return 'At least 4 digits';
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _confirm,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 6,
                      decoration: const InputDecoration(
                          labelText: 'Confirm new PIN', counterText: ''),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        if (v != _newPin.text) return 'PINs do not match';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        icon: _changing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.check),
                        label: const Text('Update PIN'),
                        onPressed: _changing
                            ? null
                            : () async {
                                if (!_formKey.currentState!.validate()) return;
                                setState(() => _changing = true);
                                final ok = await AdminGate.I.changePin(
                                  currentPin: _current.text.trim(),
                                  newPin: _newPin.text.trim(),
                                );
                                setState(() => _changing = false);
                                if (!mounted) return;
                                if (ok) {
                                  _current.clear();
                                  _newPin.clear();
                                  _confirm.clear();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text('PIN updated successfully')),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text('Current PIN is incorrect')),
                                  );
                                }
                              },
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
