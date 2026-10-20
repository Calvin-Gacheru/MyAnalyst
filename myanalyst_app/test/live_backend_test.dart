// Runs the real app client against a real backend. Skipped unless
// LIVE_API is set, e.g.:
//   flutter test test/live_backend_test.dart --dart-define=LIVE_API=http://127.0.0.1:8765
// Needs no LLM: it covers accounts, tokens and the dataset list.
@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myanalyst_app/data/http_repository.dart';
import 'package:myanalyst_app/data/repository.dart';

import 'auth_flow_test.dart' show MemoryTokenStore;

const _api = String.fromEnvironment('LIVE_API');

void main() {
  final skip = _api.isEmpty ? 'set --dart-define=LIVE_API=http://host:port' : null;
  final user = 'live${DateTime.now().millisecondsSinceEpoch}';

  HttpAnalystRepository client(MemoryTokenStore store) =>
      HttpAnalystRepository(baseUri: Uri.parse(_api), store: store);

  test('register, use, restart, refresh, reuse-safe, logout', () async {
    final store = MemoryTokenStore();
    final a = client(store);

    expect(await a.register(user, 'correct horse 1'), user);
    expect(await a.listDatasets(), isEmpty);

    // Wrong password and duplicate username map to the right failures.
    final b = client(MemoryTokenStore());
    await expectLater(b.signIn(user, 'wrong password'),
        throwsA(isA<AppException>().having((e) => e.failure, 'f', Failure.wrongCredentials)));
    await expectLater(b.register(user, 'another pass'),
        throwsA(isA<AppException>().having((e) => e.failure, 'f', Failure.usernameTaken)));

    // Access tokens live 1 minute on this server, inside the 60 s refresh
    // margin, so every call below refreshes first: rotation runs for real.
    final first = store.saved!.$1;
    expect(await a.listDatasets(), isEmpty);
    expect(store.saved!.$1, isNot(first), reason: 'refresh token rotated');

    // Parallel calls must not trip the server's reuse detection.
    await Future.wait([for (var i = 0; i < 5; i++) a.listDatasets()]);

    // "Restart the app": a new client with the same storage signs in silently.
    final restarted = client(store);
    expect(await restarted.restoreSession(), user);
    expect(await restarted.listDatasets(), isEmpty);

    // A second device stays signed in when this one logs out.
    final device2Store = MemoryTokenStore();
    final device2 = client(device2Store);
    await device2.signIn(user, 'correct horse 1');

    await restarted.signOut();
    expect(store.saved, isNull);
    expect(await client(MemoryTokenStore()..saved = null).restoreSession(), isNull);
    expect(await device2.listDatasets(), isEmpty, reason: 'other device unaffected');
  }, skip: skip);
}
