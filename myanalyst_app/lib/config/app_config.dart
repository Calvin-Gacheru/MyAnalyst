import 'package:flutter/foundation.dart';

/// Build-time configuration, set with --dart-define. There is deliberately
/// no in-app setting for the server address: a release build talks to the
/// one backend it was built for, and nothing else.
///
///   flutter run -d chrome                                   # mock data
///   flutter run -d chrome --dart-define=USE_MOCK=false \
///       --dart-define=API_BASE_URL=http://localhost:8000    # local backend
abstract final class AppConfig {
  static const useMock = bool.fromEnvironment('USE_MOCK', defaultValue: true);
  static const _apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000');

  /// Upload limit enforced before anything leaves the device. The server
  /// must enforce its own limit too; this one just saves a wasted upload.
  static const maxUploadBytes = 25 * 1024 * 1024;

  static const uploadTimeout = Duration(minutes: 5);
  static const questionTimeout = Duration(minutes: 3);
  static const requestTimeout = Duration(seconds: 20);

  static Uri get apiBase {
    final uri = Uri.parse(_apiBaseUrl);
    // Release builds must use TLS. Plain http is allowed only for local
    // development against localhost / the Android emulator host.
    if (kReleaseMode && uri.scheme != 'https') {
      throw StateError('API_BASE_URL must use https in release builds.');
    }
    return uri;
  }
}
