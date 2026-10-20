import 'package:dio/dio.dart';

import 'token_manager.dart';

/// Marks a request as not needing (or not allowed) a bearer token.
const noAuth = {'auth': false};

/// Attaches the access token to every API request and keeps it valid:
///
///  * before sending: refreshes if the token is missing or expires within
///    a minute;
///  * on a 401: refreshes once and retries the request once. Many requests
///    failing together share a single refresh (see [TokenManager.refresh]);
///  * if the server ends the session, the request fails with a 401 so the
///    app can return to sign-in.
///
/// A [QueuedInterceptor] handles requests one at a time in this stage, so
/// a burst of calls at app start doesn't fire a burst of refreshes.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor(this._tokens, this._dio);

  final TokenManager _tokens;
  final Dio _dio; // the authenticated client, used to replay requests

  static const _retriedKey = 'auth_retried';

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.extra['auth'] == false) return handler.next(options);
    try {
      final token = await _tokens.validAccessToken();
      options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    } on SessionEnded {
      handler.reject(_sessionEnded(options));
    } on DioException catch (e) {
      // Couldn't reach the server to refresh: surface it as this request's error.
      handler.reject(e.copyWith(requestOptions: options));
    }
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final retryable = err.response?.statusCode == 401 &&
        options.extra['auth'] != false &&
        options.extra[_retriedKey] != true;
    if (!retryable) return handler.next(err);

    try {
      final sent = (options.headers['Authorization'] as String?)?.replaceFirst('Bearer ', '');
      final token = await _tokens.refresh(unlessChangedFrom: sent);
      final retry = options.copyWith(
        headers: {...options.headers, 'Authorization': 'Bearer $token'},
        extra: {...options.extra, _retriedKey: true},
      );
      handler.resolve(await _dio.fetch<dynamic>(retry));
    } on SessionEnded {
      handler.next(_sessionEnded(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  static DioException _sessionEnded(RequestOptions options) => DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<void>(requestOptions: options, statusCode: 401),
        message: 'session ended',
      );
}
