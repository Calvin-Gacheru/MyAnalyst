import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myanalyst_app/data/auth/token_manager.dart';
import 'package:myanalyst_app/data/mock_repository.dart';
import 'package:myanalyst_app/data/repository.dart';
import 'package:myanalyst_app/security/app_lock.dart';
import 'package:myanalyst_app/state/app_controller.dart';

/// Secure storage backed by a map.
class MemorySecureStorage extends FlutterSecureStorage {
  MemorySecureStorage() : super();
  final Map<String, String> data = {};
  @override
  Future<String?> read({required String key, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions,
          WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async =>
      data[key];
  @override
  Future<void> write({required String key, required String? value, IOSOptions? iOptions, AndroidOptions? aOptions,
      LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<void> delete({required String key, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions,
      WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async {
    data.remove(key);
  }
}

/// Stands in for the fingerprint sensor + hardware keystore.
class FakeAppLock implements AppLock {
  bool available = true;
  bool _enabled = false;
  Uint8List? storedKey;
  bool userCancels = false;
  bool keyInvalidated = false;
  int prompts = 0;

  @override
  Future<void> init() async {}
  @override
  Future<bool> isAvailable() async => available;
  @override
  bool get enabled => _enabled;

  @override
  Future<Uint8List?> enable(LockPrompt prompt) async {
    prompts++;
    if (userCancels) return null;
    storedKey = Uint8List.fromList(List.generate(32, (i) => i));
    _enabled = true;
    return storedKey;
  }

  @override
  Future<Uint8List?> unlock(LockPrompt prompt) async {
    prompts++;
    if (keyInvalidated) throw const LockBroken();
    if (userCancels) return null;
    return storedKey;
  }

  @override
  Future<void> disable() async {
    _enabled = false;
    storedKey = null;
  }
}

/// Demo repository that "remembers" a signed-in user across restarts.
class RememberingRepo extends MockAnalystRepository {
  RememberingRepo() : super(latencyScale: 0);
  String? saved;
  Uint8List? vaultKey;
  int locks = 0;
  @override
  Future<String> signIn(String username, String password) async => saved = await super.signIn(username, password);
  @override
  Future<String?> savedUsername() async => saved;
  @override
  Future<String?> restoreSession() async => saved;
  @override
  Future<void> signOut() async => saved = null;
  @override
  Future<void> setVaultKey(Uint8List? key, {bool reseal = false}) async => vaultKey = key;
  @override
  void lockSession() => locks++;
}

void main() {
  group('sealed refresh token', () {
    test('encrypted at rest; unreadable without the key; tamper-proof', () async {
      final storage = MemorySecureStorage();
      final store = TokenStore(storage)..vaultKey = Uint8List.fromList(List.filled(32, 7));
      await store.write('refresh-token-secret-value', 'li.wei');

      expect(storage.data.values.any((v) => v.contains('refresh-token-secret-value')), isFalse,
          reason: 'plain token must not be on disk');
      expect((await store.read())!.$1, 'refresh-token-secret-value');

      final locked = TokenStore(storage);
      await expectLater(locked.read(), throwsA(isA<VaultLocked>()));
      expect(await locked.readUsername(), 'li.wei', reason: 'username shown on the lock screen');

      final wrongKey = TokenStore(storage)..vaultKey = Uint8List.fromList(List.filled(32, 8));
      expect(await wrongKey.read(), isNull);
    });

    test('turning the lock off stores the token plainly again', () async {
      final storage = MemorySecureStorage();
      final store = TokenStore(storage)..vaultKey = Uint8List.fromList(List.filled(32, 1));
      await store.write('refresh-token-secret-value', 'li.wei');
      store.vaultKey = null;
      await store.write('refresh-token-secret-value', 'li.wei');
      expect((await TokenStore(storage).read())!.$1, 'refresh-token-secret-value');
    });
  });

  group('app lock flow', () {
    late FakeAppLock lock;
    late RememberingRepo repo;
    var now = DateTime(2026, 10, 20, 9);
    AppController controller() => AppController(repo, isDemo: true, lock: lock, clock: () => now);

    setUp(() {
      lock = FakeAppLock();
      repo = RememberingRepo();
    });

    test('offered once after sign-in; turning on seals the sign-in', () async {
      final c = controller();
      await c.restore();
      await c.signIn('li.wei', 'password1', create: false);
      expect(c.offerBiometric, isTrue);
      expect(await c.setBiometric(true), isNull);
      expect(c.biometricEnabled, isTrue);
      expect(repo.vaultKey, isNotNull);
      expect(c.offerBiometric, isFalse);
    });

    test('next launch starts locked, fingerprint opens it', () async {
      final first = controller();
      await first.restore();
      await first.signIn('li.wei', 'password1', create: false);
      await first.setBiometric(true);

      final relaunch = controller();
      await relaunch.restore();
      expect(relaunch.locked, isTrue);
      expect(relaunch.signedIn, isFalse);
      expect(relaunch.lockedUser, 'li.wei');

      await relaunch.unlock();
      expect(relaunch.locked, isFalse);
      expect(relaunch.username, 'li.wei');
    });

    test('cancelling the prompt keeps the app locked', () async {
      final c = controller();
      await c.restore();
      await c.signIn('li.wei', 'password1', create: false);
      await c.setBiometric(true);
      final relaunch = controller();
      await relaunch.restore();
      lock.userCancels = true;
      await relaunch.unlock();
      expect(relaunch.locked, isTrue);
    });

    test('changed fingerprints clear the sign-in and ask for the password', () async {
      final c = controller();
      await c.restore();
      await c.signIn('li.wei', 'password1', create: false);
      await c.setBiometric(true);
      final relaunch = controller();
      await relaunch.restore();
      lock.keyInvalidated = true;
      await relaunch.unlock();
      expect(relaunch.locked, isFalse);
      expect(relaunch.signedIn, isFalse);
      expect(relaunch.lockBroken, isTrue);
      expect(lock.enabled, isFalse);
      expect(repo.saved, isNull);
    });

    test('relocks after 5 minutes in the background, not before', () async {
      final c = controller();
      await c.restore();
      await c.signIn('li.wei', 'password1', create: false);
      await c.setBiometric(true);

      c.onBackgrounded();
      now = now.add(const Duration(minutes: 4, seconds: 59));
      c.onForegrounded();
      expect(c.locked, isFalse, reason: 'under 5 minutes');

      c.onBackgrounded();
      now = now.add(const Duration(minutes: 5));
      c.onForegrounded();
      expect(c.locked, isTrue);
      expect(repo.locks, 1, reason: 'tokens wiped from memory');

      await c.unlock();
      expect(c.locked, isFalse);
      expect(c.signedIn, isTrue);
    });

    test('sign out turns the lock off', () async {
      final c = controller();
      await c.restore();
      await c.signIn('li.wei', 'password1', create: false);
      await c.setBiometric(true);
      await c.signOut();
      expect(lock.enabled, isFalse);
      expect(c.signedIn, isFalse);
    });

    test('no offer when the phone has no biometrics', () async {
      lock.available = false;
      final c = controller();
      await c.restore();
      await c.signIn('li.wei', 'password1', create: false);
      expect(c.offerBiometric, isFalse);
    });
  });

  test('NoAppLock never locks', () async {
    final c = AppController(MockAnalystRepository(latencyScale: 0), isDemo: true);
    await c.restore();
    expect(c.locked, isFalse);
    expect(await c.setBiometric(true), isNull);
    expect(c.biometricEnabled, isFalse);
  });

  test('Failure enum still maps signed-out', () => expect(const AppException(Failure.signedOut).retryable, isFalse));
}
