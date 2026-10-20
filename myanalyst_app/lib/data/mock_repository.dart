import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/models.dart';
import 'repository.dart';

/// Offline stand-in for the backend. Responses in assets/mock/ were produced
/// by the real backend pipeline on the sample CSVs (cash flow, privacy
/// report, cleaning log, Plotly charts), with prose written in English and
/// Chinese. Parsing goes through the same code the live API uses.
class MockAnalystRepository implements AnalystRepository {
  MockAnalystRepository({this.latencyScale = 1.0});

  /// Multiplier on simulated delays (0 in tests).
  final double latencyScale;

  final _rules = <String, List<BusinessRule>>{};
  final _library = <String, (String key, String fileName, DateTime at)>{};
  final _cash = <String, double>{};
  var _nextRuleId = 1;
  final _rng = math.Random(7);
  String? _user;

  Future<void> _latency(int minMs, int maxMs) => Future.delayed(
      Duration(milliseconds: ((minMs + _rng.nextInt(maxMs - minMs)) * latencyScale).round()));

  Future<Map<String, Object?>> _json(String name) async =>
      (jsonDecode(await rootBundle.loadString('assets/mock/$name')) as Map).cast<String, Object?>();

  /// Each opened sample gets its own id, so the library behaves like the
  /// server's (several analyses of the same file are separate entries).
  Future<Dataset> _load(String key, String fileName, String language, {String? id, DateTime? at}) async {
    final j = await _json('${key}_upload.json');
    if (language == 'zh') {
      if (j['executive_summary_zh'] != null) j['executive_summary'] = j['executive_summary_zh'];
      if (j['data_dictionary_zh'] != null) j['data_dictionary'] = j['data_dictionary_zh'];
    }
    final datasetId = id ?? _newId(key);
    j['dataset_id'] = datasetId;
    final at0 = at ?? DateTime.now();
    _library[datasetId] = (key, fileName, at0);
    var ds = Dataset.fromUploadJson(j, fileName: fileName, uploadedAt: at0);
    final cash = _cash[datasetId];
    if (cash != null) ds = ds.withCashFlow(_withCash(j['cashflow'], cash));
    return ds;
  }

  String _newId(String key) {
    String hex(int n) => List.generate(n, (_) => _rng.nextInt(16).toRadixString(16)).join();
    // Keep the sample key recognisable in the id for answer routing.
    final prefix = switch (key) { 'bakery' => 'b0000000', 'store' => '9b1e47d0', _ => 'c0ffee00' };
    return '$prefix-${hex(4)}-4${hex(3)}-a${hex(3)}-${hex(12)}';
  }

  // ---- account --------------------------------------------------------------

  // The demo remembers who signed in (so the biometric lock has a sign-in
  // to protect across restarts). No tokens exist in demo mode.
  static const _prefs = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  static const _userKey = 'myanalyst.demo_user';

  @override
  Future<String?> restoreSession() async => _user ??= await savedUsername();

  @override
  Future<String?> savedUsername() async {
    try {
      return await _prefs.read(key: _userKey);
    } catch (_) {
      return null; // no plugin (tests) or unreadable
    }
  }

  @override
  Future<void> setVaultKey(Uint8List? key, {bool reseal = false}) async {}

  @override
  void lockSession() {}

  @override
  Future<String> signIn(String username, String password) async {
    await _latency(400, 700);
    _user = username.trim().toLowerCase();
    try {
      await _prefs.write(key: _userKey, value: _user);
    } catch (_) {}
    return _user!;
  }

  @override
  Future<String> register(String username, String password) => signIn(username, password);

  @override
  Future<void> signOut() async {
    _user = null;
    try {
      await _prefs.delete(key: _userKey);
    } catch (_) {}
  }

  // ---- datasets -------------------------------------------------------------

  @override
  Future<Dataset> uploadDataset({
    required String fileName,
    required Uint8List bytes,
    required String language,
    void Function(double sent)? onProgress,
  }) async {
    for (var i = 1; i <= 10; i++) {
      await _latency(60, 90);
      onProgress?.call(i / 10);
    }
    await _latency(4500, 6000);
    // Any file gets the bakery analysis in demo mode.
    return _load('bakery', fileName, language);
  }

  @override
  Future<Dataset> openSample(SampleDataset sample, {required String language}) async {
    await _latency(5500, 7000);
    return _load(sample.key, sample.fileName, language);
  }

  @override
  Future<List<DatasetSummary>> listDatasets() async {
    await _latency(150, 300);
    final out = <DatasetSummary>[];
    for (final MapEntry(key: id, value: (key, name, at)) in _library.entries) {
      out.add(DatasetSummary.of(await _load(key, name, 'en', id: id, at: at)));
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  @override
  Future<Dataset> openDataset(String id, {required String language}) async {
    await _latency(300, 600);
    final entry = _library[id];
    if (entry == null) throw const AppException(Failure.notFound);
    return _load(entry.$1, entry.$2, language, id: id, at: entry.$3);
  }

  @override
  Future<void> deleteDataset(String id) async {
    await _latency(200, 400);
    _library.remove(id);
    _rules.remove(id);
    _cash.remove(id);
  }

  @override
  Future<CashFlow> recomputeCashFlow(String datasetId, double cashOnHand) async {
    await _latency(400, 800);
    final entry = _library[datasetId];
    if (entry == null) throw const AppException(Failure.notFound);
    _cash[datasetId] = cashOnHand;
    final j = await _json('${entry.$1}_upload.json');
    return _withCash(j['cashflow'], cashOnHand);
  }

  /// Same arithmetic as the backend's cashflow.py: runway = cash / burn, and
  /// the projection shifts by the change in starting cash.
  static CashFlow _withCash(Object? raw, double cash) {
    final j = Map<String, Object?>.from((raw as Map?) ?? const {});
    if (j['detected'] != true || j['mode'] == 'inflow_only') return CashFlow.fromJson(j);
    final old = (j['cash_on_hand'] as num?)?.toDouble() ?? 0;
    final burn = (j['monthly_burn'] as num?)?.toDouble() ?? 0;
    final delta = cash - old;
    final proj = [
      for (final p in (j['projection'] as List? ?? const []).cast<Map>())
        {
          'date': p['date'],
          'low': (p['low'] as num) + delta,
          'mid': (p['mid'] as num) + delta,
          'high': (p['high'] as num) + delta,
        }
    ];
    Map<String, Object?>? gap;
    final firstLow = proj.indexWhere((p) => (p['low'] as num) < 0);
    if (firstLow >= 0) {
      final firstMid = proj.indexWhere((p) => (p['mid'] as num) < 0);
      final worst = proj.map((p) => (p['low'] as num).toDouble()).reduce(math.min);
      final at = firstMid >= 0 ? firstMid : firstLow;
      gap = {
        'likelihood': firstMid >= 0 ? 'likely' : 'possible',
        'date': proj[at]['date'],
        'weeks_away': at + 1,
        'shortfall': -worst,
        'suggested_amount': ((-worst) / 10000).ceil() * 10000.0,
      };
    }
    j
      ..['cash_on_hand'] = cash
      ..['balance_source'] = 'user'
      ..['runway_months'] = burn > 0 ? (math.max(cash, 0) / burn * 10).round() / 10 : null
      ..['projection'] = proj
      ..['cash_gap'] = gap;
    return CashFlow.fromJson(j);
  }

  // ---- rules and questions --------------------------------------------------

  @override
  Future<List<BusinessRule>> listRules(String datasetId) async {
    await _latency(150, 350);
    return List.unmodifiable(_rules[datasetId] ?? const []);
  }

  @override
  Future<BusinessRule> addRule(String datasetId, String text) async {
    await _latency(200, 450);
    final rule = BusinessRule(id: _nextRuleId++, datasetId: datasetId, text: text, createdAt: DateTime.now());
    (_rules[datasetId] ??= []).add(rule);
    return rule;
  }

  @override
  Future<Answer> ask(String datasetId, String question, {String? sessionId, required String language}) async {
    await _latency(2600, 4200);
    final session = sessionId ?? 'mock-session-${DateTime.now().millisecondsSinceEpoch}';
    final all = await _json('answers.json');
    final j = Map<String, Object?>.from((all[_cannedKey(datasetId, question.toLowerCase())] as Map).cast());
    if (language == 'zh' && j['answer_zh'] != null) j['answer'] = j['answer_zh'];
    return Answer.fromJson({...j, 'session_id': session});
  }

  static String _cannedKey(String datasetId, String q) {
    if (datasetId.startsWith('9b1e47d0')) return 'store_general';
    if (datasetId.startsWith('b0000000')) {
      final costs = ['cost', 'cut', 'spend', 'save', 'expense', '成本', '节省', '支出', '开支', '省'];
      return costs.any(q.contains) ? 'bakery_costs' : 'bakery_cash';
    }
    if (q.contains('forecast') || q.contains('next month') || q.contains('predict') || q.contains('预测')) return 'giveup';
    if (['best', 'top', 'most popular', 'sell', '最', '卖', '收入'].any(q.contains)) return 'top_products';
    if (['card', 'cash', 'payment', '刷卡', '现金', '支付'].any(q.contains)) return 'payment';
    if (['day', 'week', 'busiest', '周', '天'].any(q.contains)) return 'weekday';
    return 'general';
  }
}
