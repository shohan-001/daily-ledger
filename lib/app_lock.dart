import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'constants.dart';

/// Phone-only lock. Preference is a small file next to the database, not
/// inside it, so a backup/sync cannot turn the lock on or off for you.
class AppLock extends ChangeNotifier {
  AppLock._(this._file, this._enabled)
      : _locked = _enabled && kIsMobile;

  final File _file;
  final LocalAuthentication _auth = LocalAuthentication();

  bool _enabled;
  bool _locked;
  bool _busy = false;

  bool get enabled => _enabled;
  bool get isLocked => kIsMobile && _enabled && _locked;
  bool get busy => _busy;

  static Future<AppLock> load() async {
    final Directory dir = await getApplicationSupportDirectory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final File file = File(p.join(dir.path, 'applock.enabled'));
    final bool on = file.existsSync() && file.readAsStringSync().trim() == '1';
    return AppLock._(file, on);
  }

  /// Fingerprint, face, or the phone's PIN/pattern/password.
  Future<bool> deviceCanLock() async {
    if (!kIsMobile) return false;
    try {
      return await _auth.isDeviceSupported();
    } on Object {
      return false;
    }
  }

  Future<bool> authenticate(String reason) async {
    if (!kIsMobile) return true;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      );
    } on PlatformException {
      return false;
    } on Object {
      return false;
    }
  }

  Future<bool> unlock() async {
    if (!isLocked) return true;
    if (_busy) return false;
    _busy = true;
    notifyListeners();
    final bool ok = await authenticate('Unlock DailyLedger');
    _busy = false;
    if (ok) _locked = false;
    notifyListeners();
    return ok;
  }

  void lockNow() {
    if (!_enabled || !kIsMobile || _busy) return;
    if (_locked) return;
    _locked = true;
    notifyListeners();
  }

  Future<String?> setEnabled(bool value) async {
    if (!kIsMobile) return 'Lock is only available on the phone.';
    if (value) {
      if (!await deviceCanLock()) {
        return 'Set a screen lock (PIN, pattern, or fingerprint) in Android '
            'settings first.';
      }
      final bool ok = await authenticate('Turn on DailyLedger lock');
      if (!ok) return 'Could not verify it is you.';
      _file.writeAsStringSync('1');
      _enabled = true;
      _locked = false;
    } else {
      if (_enabled) {
        final bool ok = await authenticate('Turn off DailyLedger lock');
        if (!ok) return 'Could not verify it is you.';
      }
      if (_file.existsSync()) _file.deleteSync();
      _enabled = false;
      _locked = false;
    }
    notifyListeners();
    return null;
  }
}

/// Covers the ledger until the phone unlocks. Linux always shows [child].
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppLock>().unlock();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final AppLock lock = context.read<AppLock>();
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      lock.lockNow();
    } else if (state == AppLifecycleState.resumed && lock.isLocked) {
      lock.unlock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLock lock = context.watch<AppLock>();
    if (!lock.isLocked) return widget.child;
    return const _LockScreen();
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen();

  @override
  Widget build(BuildContext context) {
    final AppLock lock = context.watch<AppLock>();
    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Icon(Icons.lock_outline, size: 40, color: kAccent),
                  const SizedBox(height: 18),
                  const Text(
                    'DailyLedger is locked',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Unlock with fingerprint, face, or your phone PIN.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kTextMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: lock.busy ? null : () => lock.unlock(),
                      icon: const Icon(Icons.fingerprint, size: 20),
                      label: Text(lock.busy ? 'Waiting…' : 'Unlock'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
