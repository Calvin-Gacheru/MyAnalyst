import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import 'auth/auth_interceptor.dart';
import 'auth/token_manager.dart';
import 'repository.dart';

/// Talks to the real FastAPI backend (MyAnalyst/main.py, workspace API)
/// through dio. One analysis in the app = one backend workspace.
///
/// Auth model: a 15-minute JWT access token (memory only) and a rotating
/// 30-day refresh token (secure storage). [AuthInterceptor] keeps the
/// access token valid, so users only sign in again after 30 days away or
/// an explicit sign-out.
class HttpAnalystRepository implements AnalystRepository {
  HttpAnalystRepository({Uri? baseUri, TokenStore? store, HttpClientAdapter? adapter}) {
    final base = BaseOptions(
      baseUrl: (baseUri ?? AppConfig.apiBase).toString().replaceAll(RegExp(r'/+$'), ''),
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: AppConfig.requestTimeout,
      receiveTimeout: AppConfig.requestTimeout,
      headers: {'Accept': 'application/json'},
      responseType: ResponseType.json,
    );
    _authDio = Dio(base);
    _dio = Dio(base);
    if (adapter != null) {
      _authDio.httpClientAdapter = adapter;
      _dio.httpClientAdapter = adapter;
    }
    _store = store ?? TokenStore();
    tokens = TokenManager(authDio: _authDio, store: _store);
    _dio.interceptors.add(AuthInterceptor(tokens, _dio));
  }

  late final Dio _authDio; // /auth/* only, no interceptor
  late final Dio _dio; // everything else
  late final TokenManager tokens;
  late final TokenStore _store;

  /// Dataset ids are server-issued UUIDs; refuse anything else so a tampered
  /// id can't be used to build an unexpected path.
  static final _uuid = RegExp(r'^[0-9a-fA-F-]{36}$');
  String _id(String id) {
    if (!_uuid.hasMatch(id)) throw const AppException(Failure.notFound);
    return Uri.encodeComponent(id);
  }

  // ---- account --------------------------------------------------------------

  @override
  Future<String?> restoreSession() async {
    try {
      if (!await tokens.load()) return null;
    } on VaultLocked {
      return null; // the controller unlocks the vault before restoring
    }
    try {
      await tokens.refresh();
      return tokens.username;
    } on SessionEnded {
      return null;
    } on DioException {
      // Offline at launch: keep the user signed in; the interceptor will
      // refresh on the first request once the network is back.
      return tokens.username;
    }
  }

  Future<String> _authenticate(String path, String username, String password, Failure conflict) async {
    final json = await _call(
      () => _authDio.post<Map<String, Object?>>(path, data: {'username': username.trim(), 'password': password}),
      authCall: true,
      conflict: conflict,
    );
    await tokens.accept(json!);
    return tokens.username ?? username;
  }

  @override
  Future<String> signIn(String username, String password) =>
      _authenticate('/auth/login', username, password, Failure.rejected);

  @override
  Future<String> register(String username, String password) =>
      _authenticate('/auth/register', username, password, Failure.usernameTaken);

  @override
  Future<void> signOut() => tokens.signOut(); // this device only

  @override
  Future<String?> savedUsername() => _store.readUsername();

  @override
  Future<void> setVaultKey(Uint8List? key, {bool reseal = false}) => tokens.setVaultKey(key, reseal: reseal);

  @override
  void lockSession() => tokens.lock();

  // ---- datasets -------------------------------------------------------------

  @override
  Future<Dataset> uploadDataset({
    required String fileName,
    required Uint8List bytes,
    required String language,
    void Function(double sent)? onProgress,
  }) async {
    final form = FormData.fromMap({
      'files': [MultipartFile.fromBytes(bytes, filename: fileName)],
    });
    final json = await _call(() => _dio.post<Map<String, Object?>>(
          '/workspaces/new/files',
          data: form,
          options: Options(sendTimeout: AppConfig.uploadTimeout, receiveTimeout: AppConfig.uploadTimeout),
          onSendProgress: onProgress == null ? null : (sent, total) => onProgress(total > 0 ? sent / total : 0),
        ));
    return datasetFromWorkspaceJson(json!, fallbackName: fileName);
  }

  @override
  Future<Dataset> openSample(SampleDataset sample, {required String language}) async {
    // Samples ship as CSVs in the app bundle and go through the normal upload.
    final data = await rootBundle.load('assets/mock/${sample.fileName}');
    return uploadDataset(fileName: sample.fileName, bytes: data.buffer.asUint8List(), language: language);
  }

  @override
  Future<List<DatasetSummary>> listDatasets() async {
    final json = await _call(() => _dio.get<List<dynamic>>('/workspaces'));
    return json!.whereType<Map>().map((m) => DatasetSummary.fromWorkspaceJson(m.cast())).toList();
  }

  @override
  Future<Dataset> openDataset(String id, {required String language}) async {
    final json = await _call(() => _dio.get<Map<String, Object?>>('/workspaces/${_id(id)}'));
    return datasetFromWorkspaceJson(json!);
  }

  @override
  Future<void> deleteDataset(String id) async {
    await _call(() => _dio.delete<void>('/workspaces/${_id(id)}'));
  }

  @override
  Future<CashFlow> recomputeCashFlow(String datasetId, double cashOnHand) async {
    final json = await _call(() => _dio.get<Map<String, Object?>>(
          '/workspaces/${_id(datasetId)}/cashflow',
          queryParameters: {'cash_on_hand': cashOnHand.toStringAsFixed(2)},
        ));
    return CashFlow.fromJson(json);
  }

  // ---- rules and questions --------------------------------------------------

  @override
  Future<List<BusinessRule>> listRules(String datasetId) async {
    final json = await _call(() => _dio.get<List<dynamic>>('/workspaces/${_id(datasetId)}/business-rules'));
    return json!.whereType<Map>().map((m) => BusinessRule.fromJson(m.cast())).toList();
  }

  @override
  Future<BusinessRule> addRule(String datasetId, String text) async {
    final json = await _call(
        () => _dio.post<Map<String, Object?>>('/workspaces/${_id(datasetId)}/business-rules', data: {'rule_text': text}));
    return BusinessRule.fromJson(json!);
  }

  @override
  Future<Answer> ask(String datasetId, String question, {String? sessionId, required String language}) async {
    final json = await _call(() => _dio.post<Map<String, Object?>>(
          '/workspaces/${_id(datasetId)}/qa',
          data: {'question': question, if (sessionId != null) 'session_id': sessionId},
          options: Options(receiveTimeout: AppConfig.questionTimeout),
        ));
    return Answer.fromJson(json!);
  }

  /// Runs a request and turns every failure into an [AppException]. Server
  /// `detail` strings are only logged in debug builds, never shown.
  Future<T?> _call<T>(
    Future<Response<T>> Function() request, {
    bool authCall = false,
    Failure conflict = Failure.rejected,
  }) async {
    try {
      return (await request()).data;
    } on SessionEnded {
      throw const AppException(Failure.signedOut);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (kDebugMode) debugPrint('[api] ${e.requestOptions.method} ${e.requestOptions.path} -> ${code ?? e.type.name}');
      if (code == null) {
        throw AppException(switch (e.type) {
          DioExceptionType.connectionTimeout ||
          DioExceptionType.sendTimeout ||
          DioExceptionType.receiveTimeout =>
            Failure.timeout,
          DioExceptionType.badResponse => Failure.unreadable,
          _ => e.error is FormatException ? Failure.unreadable : Failure.network,
        });
      }
      throw AppException(switch (code) {
        400 || 422 => Failure.rejected,
        401 => authCall ? Failure.wrongCredentials : Failure.signedOut,
        403 => Failure.signedOut,
        404 => Failure.notFound,
        409 => conflict,
        413 => Failure.tooLarge,
        429 => Failure.rateLimited,
        _ => Failure.server,
      });
    } on FormatException {
      throw const AppException(Failure.unreadable);
    }
  }
}
