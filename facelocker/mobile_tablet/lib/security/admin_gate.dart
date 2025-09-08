import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simple, persistent admin gate with PIN + session timeout.
/// Usage:
///   await AdminGate.I.init();   // call once (e.g., in main)
///   final ok = await AdminGate.I.ensure(context);
///   if (ok) { /* admin area */ }
class AdminGate extends ChangeNotifier {
  AdminGate._();
  static final AdminGate I = AdminGate._();

  static const _kPinHashKey = 'admin_pin_hash_v1';
  static const _kUntilKey = 'admin_until_epoch_ms_v1';
  static const _kSalt = 'facelocker-adminpin-v1';
  static const _kDefaultPin = '1234';

  bool _loaded = false;
  String _pinHash = '';
  DateTime? _validUntil;

  bool get isLoaded => _loaded;
  bool get isActive =>
      _validUntil != null && DateTime.now().isBefore(_validUntil!);
  DateTime? get validUntil => _validUntil;

  Future<void> init() async {
    if (_loaded) return;
    final sp = await SharedPreferences.getInstance();
    _pinHash = sp.getString(_kPinHashKey) ?? _hash(_kDefaultPin);
    final untilMs = sp.getInt(_kUntilKey);
    if (untilMs != null) {
      _validUntil = DateTime.fromMillisecondsSinceEpoch(untilMs);
      if (!isActive) _validUntil = null; // clean expired
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> lock() async {
    _validUntil = null;
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kUntilKey);
    notifyListeners();
  }

  Future<void> extend({Duration duration = const Duration(minutes: 10)}) async {
    _validUntil = DateTime.now().add(duration);
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kUntilKey, _validUntil!.millisecondsSinceEpoch);
    notifyListeners();
  }

  bool verifyPin(String pin) => _hash(pin) == _pinHash;

  Future<bool> changePin(
      {required String currentPin, required String newPin}) async {
    await init();
    if (!verifyPin(currentPin)) return false;
    final sp = await SharedPreferences.getInstance();
    _pinHash = _hash(newPin);
    await sp.setString(_kPinHashKey, _pinHash);
    return true;
  }

  /// Ensure user is authorized; shows a PIN dialog if needed.
  /// Remembers the session by [rememberFor] on success.
  Future<bool> ensure(BuildContext context,
      {Duration rememberFor = const Duration(minutes: 10)}) async {
    await init();
    if (isActive) return true;
    final ok = await _showPinDialog(context, rememberFor: rememberFor);
    return ok;
  }

  static String _hash(String pin) =>
      sha256.convert(utf8.encode('$_kSalt::$pin')).toString();

  Future<bool> _showPinDialog(BuildContext context,
      {required Duration rememberFor}) async {
    final controller = TextEditingController();
    bool remember = true;
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: const Text('Admin access'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    obscureText: true,
                    maxLength: 6,
                    decoration: InputDecoration(
                      labelText: 'Enter PIN',
                      counterText: '',
                      errorText: error,
                    ),
                    onSubmitted: (_) => _try(ctx, controller, remember,
                        rememberFor, setState, (e) => error = e),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title:
                        Text('Remember for ${rememberFor.inMinutes} minutes'),
                    value: remember,
                    onChanged: (v) => setState(() => remember = v),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => _try(ctx, controller, remember, rememberFor,
                      setState, (e) => error = e),
                  child: const Text('Unlock'),
                ),
              ],
            );
          },
        );
      },
    );

    return ok == true;
  }

  void _try(
    BuildContext ctx,
    TextEditingController controller,
    bool remember,
    Duration rememberFor,
    void Function(void Function()) setState,
    void Function(String?) setError,
  ) async {
    final pin = controller.text.trim();
    if (pin.isEmpty) {
      setState(() => setError('PIN is required'));
      return;
    }
    if (!verifyPin(pin)) {
      setState(() => setError('Incorrect PIN'));
      return;
    }
    if (remember) {
      await extend(duration: rememberFor);
    } else {
      await extend(duration: const Duration(seconds: 1));
    }
    if (ctx.mounted) Navigator.of(ctx).pop(true);
  }
}
