import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thrown when the server says the sign-in is over (refresh rejected).
class SessionEnded implements Exception {
  const SessionEnded();
}

/// The stored refresh token is encrypted and no vault key is loaded yet
/// (the biometric lock hasn't been unlocked).
class VaultLocked implements Exception {
  const VaultLocked();
}

/// Persists only the refresh token and username, in the platform's secure
/// storage (Android Keystore-backed EncryptedSharedPreferences, iOS
/// Keychain). The access token lives in memory and dies with the process.
///
/// With the biometric lock on, the refresh token is additionally encrypted
/// with AES-256-GCM under a key that only a fingerprint can release (see
/// security/app_lock.dart). Without that key the stored token is useless.
class TokenStore {
  TokenStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
            );

  final FlutterSecureStorage _storage;
  static const _refreshKey = 'myanalyst.refresh_token';
  static const _sealedKey = 'myanalyst.refresh_token.sealed';
  static const _userKey = 'myanalyst.username';
  static final _aes = AesGcm.with256bits();

  /// Key from the biometric vault; null when the lock is off or locked.
  Uint8List? vaultKey;

  Future<String?> readUsername() async {
    try {
      return await _storage.read(key: _userKey);
    } catch (_) {
      return null;
    }
  }

  /// Throws [VaultLocked] if the token is sealed and no key is loaded.
  Future<(String refreshToken, String username)?> read() async {
    String? u, r, sealed;
    try {
      u = await _storage.read(key: _userKey);
      r = await _storage.read(key: _refreshKey);
      sealed = await _storage.read(key: _sealedKey);
    } catch (_) {
      return null; // unreadable keystore entry: treat as signed out
    }
    if (u == null) return null;
    if (sealed != null) {
      final key = vaultKey;
      if (key == null) throw const VaultLocked();
      try {
        final box = SecretBox.fromConcatenation(base64Decode(sealed), nonceLength: 12, macLength: 16);
        r = utf8.decode(await _aes.decrypt(box, secretKey: SecretKey(key)));
      } catch (_) {
        return null; // wrong key or tampered: the sign-in can't be used
      }
    }
    return r == null || r.isEmpty ? null : (r, u);
  }

  Future<void> write(String refreshToken, String username) async {
    final key = vaultKey;
    if (key != null) {
      final box = await _aes.encrypt(utf8.encode(refreshToken), secretKey: SecretKey(key), nonce: _aes.newNonce());
      await _storage.write(key: _sealedKey, value: base64Encode(box.concatenation()));
      await _storage.delete(key: _refreshKey);
    } else {
      await _storage.write(key: _refreshKey, value: refreshToken);
      await _storage.delete(key: _sealedKey);
    }
    await _storage.write(key: _userKey, value: username);
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _refreshKey);
      await _storage.delete(key: _sealedKey);
      await _storage.delete(key: _userKey);
    } catch (_) {}
  }
}

/// Holds the current token pair and performs refreshes.
///
/// Only one refresh runs at a time: concurrent callers share the same
/// in-flight future. That matters because the server rotates refresh
/// tokens and treats a second use of the same token as theft.
class TokenManager {
  TokenManager({required Dio authDio, TokenStore? store, DateTime Function()? clock})
      : _dio = authDio,
        _store = store ?? TokenStore(),
        _now = clock ?? DateTime.now;

  /// A Dio *without* the auth interceptor, used for /auth/* calls.
  final Dio _dio;
  final TokenStore _store;
  final DateTime Function() _now;

  /// Refresh this long before the access token actually expires.
  static const refreshMargin = Duration(seconds: 60);

  String? _access;
  DateTime? _accessExpiry;
  String? _refresh;
  String? username;
  Future<String>? _inflight;

  bool get hasSession => _refresh != null;
  String? get accessToken => _access;

  bool get accessIsFresh =>
      _access != null && _accessExpiry != null && _accessExpiry!.isAfter(_now().add(refreshMargin));

  /// Loads the saved refresh token, if any. Doesn't touch the network.
  Future<bool> load() async {
    final saved = await _store.read();
    if (saved == null) return false;
    _refresh = saved.$1;
    username = saved.$2;
    return true;
  }

  /// Stores a pair returned by login, register or refresh.
  Future<void> accept(Map<String, Object?> json) async {
    final access = json['access_token'] as String;
    final refresh = json['refresh_token'] as String;
    final user = (json['username'] as String?) ?? username ?? '';
    final expiresIn = (json['expires_in'] as num?)?.toInt();
    _access = access;
    // Trust the JWT's own exp claim; fall back to expires_in.
    _accessExpiry = jwtExpiry(access) ?? (expiresIn != null ? _now().add(Duration(seconds: expiresIn)) : null);
    _refresh = refresh;
    username = user;
    await _store.write(refresh, user);
  }

  /// A usable access token, refreshing first if it's missing or about to
  /// expire. Throws [SessionEnded] if the server ended the sign-in, or a
  /// [DioException] if the network failed (the session is kept).
  Future<String> validAccessToken() async {
    if (accessIsFresh) return _access!;
    return refresh();
  }

  /// Refreshes now. If [unlessChangedFrom] is given and the access token has
  /// already moved on (another request refreshed meanwhile), just returns
  /// the current one instead of spending another refresh.
  Future<String> refresh({String? unlessChangedFrom}) {
    if (unlessChangedFrom != null && _access != null && _access != unlessChangedFrom && accessIsFresh) {
      return Future.value(_access!);
    }
    return _inflight ??= _doRefresh().whenComplete(() => _inflight = null);
  }

  Future<String> _doRefresh() async {
    final token = _refresh;
    if (token == null) throw const SessionEnded();
    try {
      final res = await _dio.post<Map<String, Object?>>('/auth/refresh', data: {'refresh_token': token});
      await accept(res.data!);
      return _access!;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403 || code == 422) {
        await clear();
        throw const SessionEnded();
      }
      rethrow; // offline / server error: keep the session and try later
    }
  }

  /// Sets the biometric vault key. With [reseal], the current refresh token
  /// is rewritten under the new protection (encrypted, or back to plain
  /// when [key] is null).
  Future<void> setVaultKey(Uint8List? key, {bool reseal = false}) async {
    _store.vaultKey = key;
    if (reseal && _refresh != null) await _store.write(_refresh!, username ?? '');
  }

  /// App locked: forget everything sensitive held in memory. The sealed
  /// refresh token stays on disk until the next biometric unlock.
  void lock() {
    _access = null;
    _accessExpiry = null;
    _refresh = null;
    _store.vaultKey = null;
  }

  /// Revokes this device's sign-in on the server (best effort) and forgets
  /// all tokens locally. Never throws.
  Future<void> signOut() async {
    final token = _refresh;
    await clear();
    if (token == null) return;
    try {
      await _dio.post<void>('/auth/logout', data: {'refresh_token': token});
    } catch (_) {
      // Local sign-out must always succeed; the server token expires anyway.
    }
  }

  Future<void> clear() async {
    _access = null;
    _accessExpiry = null;
    _refresh = null;
    await _store.clear();
  }
}

/// Reads `exp` from a JWT payload without verifying it. Verification is the
/// server's job; the client only needs to know when to refresh.
DateTime? jwtExpiry(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    final exp = (payload as Map)['exp'];
    return exp is num ? DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true) : null;
  } catch (_) {
    return null;
  }
}
