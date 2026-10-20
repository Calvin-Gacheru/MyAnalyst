import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myanalyst_app/data/auth/token_manager.dart';
import 'package:myanalyst_app/data/http_repository.dart';
import 'package:myanalyst_app/data/repository.dart';

/// In-memory replacement for secure storage.
class MemoryTokenStore extends TokenStore {
  (String, String)? saved;
  @override
  Future<(String, String)?> read() async => saved;
  @override
  Future<void> write(String refreshToken, String username) async => saved = (refreshToken, username);
  @override
  Future<void> clear() async => saved = null;
}

String _jwt(int expEpochSeconds, String id) {
  String b64(Map<String, Object> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${b64({'alg': 'HS256'})}.${b64({'exp': expEpochSeconds, 'jti': id})}.sig';
}

/// Behaves like main.py's auth: rotating refresh tokens with reuse
/// detection, access tokens checked on every protected call.
class FakeServer implements HttpClientAdapter {
  int refreshCalls = 0;
  int logoutCalls = 0;
  bool networkDown = false;
  int accessLifetimeSeconds = 900;
  final Set<String> validAccess = {};
  final Set<String> liveRefresh = {};
  final Set<String> spentRefresh = {};
  int _n = 0;

  Map<String, Object> issue() {
    _n++;
    final access = _jwt(DateTime.now().millisecondsSinceEpoch ~/ 1000 + accessLifetimeSeconds, 'a$_n');
    final refresh = 'refresh-token-number-$_n-padding-padding';
    validAccess.add(access);
    liveRefresh.add(refresh);
    return {'access_token': access, 'refresh_token': refresh, 'expires_in': accessLifetimeSeconds, 'username': 'li.wei'};
  }

  ResponseBody _json(Object body, int status) => ResponseBody.fromString(jsonEncode(body), status,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (networkDown) {
      throw DioException.connectionError(requestOptions: o, reason: 'offline');
    }
    switch (o.path) {
      case '/auth/login':
        return _json(issue(), 200);
      case '/auth/refresh':
        refreshCalls++;
        final token = (o.data as Map)['refresh_token'] as String;
        if (spentRefresh.contains(token)) {
          liveRefresh.clear(); // reuse = theft: revoke the family
          return _json({'detail': 'Session ended.'}, 401);
        }
        if (!liveRefresh.remove(token)) return _json({'detail': 'Session ended.'}, 401);
        spentRefresh.add(token);
        return _json(issue(), 200);
      case '/auth/logout':
        logoutCalls++;
        liveRefresh.remove((o.data as Map)['refresh_token']);
        return _json({}, 204);
      default:
        final auth = (o.headers['Authorization'] as String?)?.replaceFirst('Bearer ', '');
        if (auth == null || !validAccess.contains(auth)) return _json({'detail': 'Sign in required.'}, 401);
        return _json([], 200); // GET /datasets -> empty list
    }
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late FakeServer server;
  late MemoryTokenStore store;
  late HttpAnalystRepository repo;

  setUp(() {
    server = FakeServer();
    store = MemoryTokenStore();
    repo = HttpAnalystRepository(baseUri: Uri.parse('http://test'), store: store, adapter: server);
  });

  test('sign in stores only the refresh token; access stays in memory', () async {
    expect(await repo.signIn('li.wei', 'password1'), 'li.wei');
    expect(store.saved!.$1, startsWith('refresh-token-number-1'));
    expect(repo.tokens.accessToken, isNotNull);
    expect(await repo.listDatasets(), isEmpty);
    expect(server.refreshCalls, 0);
  });

  test('a token about to expire is refreshed before the request is sent', () async {
    server.accessLifetimeSeconds = 30; // inside the 60 s margin
    await repo.signIn('li.wei', 'password1');
    await repo.listDatasets();
    expect(server.refreshCalls, 1);
  });

  test('parallel requests with an expired token share ONE refresh', () async {
    server.accessLifetimeSeconds = 30;
    await repo.signIn('li.wei', 'password1');
    server.accessLifetimeSeconds = 900;
    await Future.wait([for (var i = 0; i < 6; i++) repo.listDatasets()]);
    expect(server.refreshCalls, 1); // a second use of the same refresh token would have revoked the session
  });

  test('401 on a fresh-looking token: refresh once, retry, succeed', () async {
    await repo.signIn('li.wei', 'password1');
    server.validAccess.clear(); // e.g. server restarted with a new secret
    expect(await repo.listDatasets(), isEmpty);
    expect(server.refreshCalls, 1);
  });

  test('rejected refresh ends the session cleanly', () async {
    await repo.signIn('li.wei', 'password1');
    server.validAccess.clear();
    server.liveRefresh.clear(); // e.g. revoked by logout on this device elsewhere
    await expectLater(repo.listDatasets(), throwsA(isA<AppException>().having((e) => e.failure, 'failure', Failure.signedOut)));
    expect(store.saved, isNull);
  });

  test('going offline keeps the session', () async {
    server.accessLifetimeSeconds = 30;
    await repo.signIn('li.wei', 'password1');
    server.networkDown = true;
    await expectLater(repo.listDatasets(), throwsA(isA<AppException>().having((e) => e.failure, 'failure', Failure.network)));
    expect(store.saved, isNotNull);
    server.networkDown = false;
    server.accessLifetimeSeconds = 900;
    expect(await repo.listDatasets(), isEmpty);
  });

  test('app restart signs in silently from the stored refresh token', () async {
    await repo.signIn('li.wei', 'password1');
    final restarted = HttpAnalystRepository(baseUri: Uri.parse('http://test'), store: store, adapter: server);
    expect(await restarted.restoreSession(), 'li.wei');
    expect(await restarted.listDatasets(), isEmpty);
  });

  test('sign out revokes this device and forgets the tokens', () async {
    await repo.signIn('li.wei', 'password1');
    await repo.signOut();
    expect(server.logoutCalls, 1);
    expect(store.saved, isNull);
    final restarted = HttpAnalystRepository(baseUri: Uri.parse('http://test'), store: store, adapter: server);
    expect(await restarted.restoreSession(), isNull);
  });

  test('jwtExpiry reads exp without verifying', () {
    final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 100;
    expect(jwtExpiry(_jwt(exp, 'x'))!.millisecondsSinceEpoch, exp * 1000);
    expect(jwtExpiry('not-a-jwt'), isNull);
  });
}
