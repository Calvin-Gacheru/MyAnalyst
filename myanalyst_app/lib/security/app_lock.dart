import 'dart:convert';
import 'dart:math';

import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Text for the system biometric prompt, in the app's current language.
class LockPrompt {
  const LockPrompt({required this.title, required this.subtitle, required this.cancel});
  final String title;
  final String subtitle;
  final String cancel;
}

/// The stored key can no longer be read: fingerprints were added or removed
/// on the device (the OS invalidates the key), or the keystore was reset.
class LockBroken implements Exception {
  const LockBroken();
}

/// Biometric app lock.
///
/// A random 256-bit key is kept in hardware-backed storage that releases it
/// only after a successful biometric check (Android Keystore with
/// user-authentication required; iOS Keychain with `.biometryCurrentSet`).
/// That key encrypts the refresh token (see TokenStore), so without the
/// fingerprint the sign-in can't be used, even on a rooted phone where a
/// plain "auth succeeded" flag could be faked.
abstract interface class AppLock {
  /// Loads the on/off preference. Call once at start-up.
  Future<void> init();

  /// True if the device has biometrics enrolled and the plugin supports it.
  Future<bool> isAvailable();

  bool get enabled;

  /// Creates and stores a new key (shows the biometric prompt) and turns the
  /// lock on. Returns the key, or null if the user cancelled.
  Future<Uint8List?> enable(LockPrompt prompt);

  /// Shows the biometric prompt and returns the key, or null if cancelled.
  /// Throws [LockBroken] if the key was invalidated.
  Future<Uint8List?> unlock(LockPrompt prompt);

  /// Deletes the key and turns the lock off.
  Future<void> disable();
}

class BiometricAppLock implements AppLock {
  BiometricAppLock({FlutterSecureStorage? prefs, BiometricStorage? plugin})
      : _prefs = prefs ?? const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true)),
        _plugin = plugin ?? BiometricStorage();

  final FlutterSecureStorage _prefs;
  final BiometricStorage _plugin;
  static const _flagKey = 'myanalyst.biometric_lock';
  static const _fileName = 'myanalyst_vault_key';

  bool _enabled = false;

  @override
  bool get enabled => _enabled;

  @override
  Future<void> init() async {
    try {
      _enabled = await _prefs.read(key: _flagKey) == '1';
    } catch (_) {
      _enabled = false;
    }
  }

  @override
  Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      return await _plugin.canAuthenticate() == CanAuthenticateResponse.success;
    } catch (_) {
      return false;
    }
  }

  Future<BiometricStorageFile> _file(LockPrompt p) => _plugin.getStorage(
        _fileName,
        // -1: a fresh biometric check for every read; requires biometric-only
        // on Android (no PIN fallback). The password is the fallback.
        options: StorageFileInitOptions(
          authenticationRequired: true,
          authenticationValidityDurationSeconds: -1,
          androidBiometricOnly: true,
          darwinBiometricOnly: true,
        ),
        promptInfo: PromptInfo(
          androidPromptInfo: AndroidPromptInfo(title: p.title, subtitle: p.subtitle, negativeButton: p.cancel),
          iosPromptInfo: IosPromptInfo(saveTitle: p.title, accessTitle: p.title),
          macOsPromptInfo: IosPromptInfo(saveTitle: p.title, accessTitle: p.title),
        ),
      );

  @override
  Future<Uint8List?> enable(LockPrompt prompt) async {
    final rnd = Random.secure();
    final key = Uint8List.fromList(List<int>.generate(32, (_) => rnd.nextInt(256)));
    try {
      await (await _file(prompt)).write(base64Encode(key));
    } on AuthException catch (e) {
      if (_isCancel(e)) return null;
      rethrow;
    }
    await _prefs.write(key: _flagKey, value: '1');
    _enabled = true;
    return key;
  }

  @override
  Future<Uint8List?> unlock(LockPrompt prompt) async {
    try {
      final raw = await (await _file(prompt)).read();
      if (raw == null || raw.isEmpty) throw const LockBroken();
      return base64Decode(raw);
    } on AuthException catch (e) {
      if (_isCancel(e)) return null;
      throw const LockBroken();
    } on LockBroken {
      rethrow;
    } catch (_) {
      // KeyPermanentlyInvalidatedException and friends surface here.
      throw const LockBroken();
    }
  }

  @override
  Future<void> disable() async {
    _enabled = false;
    try {
      await _prefs.delete(key: _flagKey);
    } catch (_) {}
    try {
      // Deleting needs no prompt when no PromptInfo-gated read happens.
      await (await _file(const LockPrompt(title: 'MyAnalyst', subtitle: '', cancel: 'Cancel'))).delete();
    } catch (_) {}
  }

  static bool _isCancel(AuthException e) =>
      e.code == AuthExceptionCode.userCanceled || e.code == AuthExceptionCode.canceled ||
      e.code == AuthExceptionCode.timeout;
}

/// Used where biometrics can't exist (web, tests that don't need them).
class NoAppLock implements AppLock {
  const NoAppLock();
  @override
  Future<void> init() async {}
  @override
  Future<bool> isAvailable() async => false;
  @override
  bool get enabled => false;
  @override
  Future<Uint8List?> enable(LockPrompt prompt) async => null;
  @override
  Future<Uint8List?> unlock(LockPrompt prompt) async => null;
  @override
  Future<void> disable() async {}
}
