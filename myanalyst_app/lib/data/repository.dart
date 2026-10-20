import 'dart:typed_data';

import '../models/models.dart';

/// Everything the UI needs from the backend. The mock and HTTP
/// implementations are interchangeable; the UI never knows which it has.
abstract interface class AnalystRepository {
  // ---- account --------------------------------------------------------------
  /// Restores a saved session, returning the username, or null if none.
  Future<String?> restoreSession();
  Future<String> signIn(String username, String password);
  Future<String> register(String username, String password);
  Future<void> signOut();

  /// Username of the saved sign-in, readable while the app is still locked.
  Future<String?> savedUsername();

  /// Biometric vault key for the stored sign-in (null = no lock). With
  /// [reseal], the stored refresh token is re-protected under the new key.
  Future<void> setVaultKey(Uint8List? key, {bool reseal = false});

  /// App locked: drop tokens held in memory.
  void lockSession();

  // ---- datasets -------------------------------------------------------------
  /// [onProgress] receives the share of the file sent so far (0..1).
  Future<Dataset> uploadDataset({
    required String fileName,
    required Uint8List bytes,
    required String language,
    void Function(double sent)? onProgress,
  });

  /// Loads a bundled sample as if it had been uploaded.
  Future<Dataset> openSample(SampleDataset sample, {required String language});

  Future<List<DatasetSummary>> listDatasets();
  Future<Dataset> openDataset(String id, {required String language});
  Future<void> deleteDataset(String id);

  /// Recomputes runway and the projection with the owner's real cash balance.
  Future<CashFlow> recomputeCashFlow(String datasetId, double cashOnHand);

  // ---- rules and questions --------------------------------------------------
  Future<List<BusinessRule>> listRules(String datasetId);
  Future<BusinessRule> addRule(String datasetId, String text);

  Future<Answer> ask(String datasetId, String question, {String? sessionId, required String language});
}

class SampleDataset {
  const SampleDataset({
    required this.key,
    required this.fileName,
    required this.description,
    required this.descriptionZh,
    required this.rows,
    required this.columns,
    this.featured = false,
  });

  final String key;
  final String fileName;
  final String description;
  final String descriptionZh;
  final int rows;
  final int columns;
  final bool featured;
}

const sampleDatasets = [
  SampleDataset(
    key: 'bakery',
    fileName: 'bakery_transactions.csv',
    description: 'A year of bank transactions for a Shenzhen bakery. Shows cash flow, runway and financing.',
    descriptionZh: '深圳一家烘焙店一整年的银行流水，可查看现金流、可维持时间和融资方式。',
    rows: 1305,
    columns: 6,
    featured: true,
  ),
  SampleDataset(
    key: 'coffee',
    fileName: 'coffee_sales.csv',
    description: 'Six weeks of till receipts from a small coffee shop.',
    descriptionZh: '一家小咖啡店六周的收银记录。',
    rows: 262,
    columns: 5,
  ),
  SampleDataset(
    key: 'store',
    fileName: 'store_sales.csv',
    description: 'Purchases across nine departments at a general store, with ratings and discounts.',
    descriptionZh: '一家综合零售店九个部门的购买记录，含评分和折扣。',
    rows: 5000,
    columns: 11,
  ),
];

/// Why a request failed. The UI turns each kind into a message in the
/// current language, so raw server text, stack traces and file paths never
/// reach the screen.
enum Failure {
  network,
  timeout,
  rejected, // 400 / 422
  signedOut, // 401
  wrongCredentials,
  usernameTaken,
  notFound,
  tooLarge,
  rateLimited,
  server,
  unreadable,
}

class AppException implements Exception {
  const AppException(this.failure);

  final Failure failure;

  bool get retryable => switch (failure) {
        Failure.network || Failure.timeout || Failure.rateLimited || Failure.server => true,
        _ => false,
      };

  @override
  String toString() => 'AppException($failure)';
}
