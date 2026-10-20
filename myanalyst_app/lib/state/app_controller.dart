import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../config/app_config.dart';
import '../data/repository.dart';
import '../i18n/strings.dart';
import '../models/models.dart';
import '../security/app_lock.dart';

enum Section { overview, cash, data, ask, rules }

enum FileProblem { notCsv, empty, tooBig, binary }

/// Single source of truth for the UI. Screens read from it and call its
/// methods; they never talk to the repository directly.
class AppController extends ChangeNotifier {
  AppController(
    this._repo, {
    required this.isDemo,
    AppLanguage language = AppLanguage.en,
    AppLock lock = const NoAppLock(),
    DateTime Function()? clock,
  })  : _language = language,
        _lock = lock,
        _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  final AnalystRepository _repo;
  final bool isDemo;

  // ---- language -------------------------------------------------------------

  AppLanguage _language;
  AppLanguage get language => _language;
  S get strings => S(_language);
  String get _lang => _language == AppLanguage.zh ? 'zh' : 'en';

  /// Switching language re-opens the current analysis so the AI-written text
  /// (summary, column meanings) comes back in the new language too.
  Future<void> toggleLanguage() async {
    _language = _language == AppLanguage.en ? AppLanguage.zh : AppLanguage.en;
    notifyListeners();
    final ds = dataset;
    if (ds != null) {
      try {
        final reopened = await _repo.openDataset(ds.id, language: _lang);
        if (dataset?.id == ds.id) {
          dataset = reopened.cashFlow.detected ? reopened : reopened.withCashFlow(ds.cashFlow);
          notifyListeners();
        }
      } on AppException catch (e) {
        _handle(e);
      }
    }
  }

  // ---- account --------------------------------------------------------------

  String? username;
  bool restoring = true;
  bool authBusy = false;
  Failure? authError;

  bool get signedIn => username != null;

  Future<void> restore() async {
    try {
      await _lock.init();
      biometricAvailable = await _lock.isAvailable();
      if (_lock.enabled) {
        // Don't touch the sign-in until the fingerprint releases its key.
        lockedUser = await _repo.savedUsername();
        if (lockedUser == null) {
          await _lock.disable(); // nothing left to protect
        } else {
          locked = true;
          return;
        }
      }
      username = await _repo.restoreSession();
      if (username != null) unawaited(loadLibrary());
    } finally {
      restoring = false;
      notifyListeners();
    }
  }

  Future<void> signIn(String user, String password, {required bool create}) async {
    if (authBusy) return;
    authBusy = true;
    authError = null;
    notifyListeners();
    try {
      username = create ? await _repo.register(user, password) : await _repo.signIn(user, password);
      unawaited(loadLibrary());
      // Offer the fingerprint once per sign-in, if the phone supports it.
      offerBiometric = biometricAvailable && !_lock.enabled;
    } on AppException catch (e) {
      authError = e.failure;
    } catch (_) {
      authError = Failure.server;
    } finally {
      authBusy = false;
      notifyListeners();
    }
  }

  /// Signs out this device. The biometric lock goes too: it protected a
  /// sign-in that no longer exists.
  Future<void> signOut() async {
    await _lock.disable();
    await _repo.setVaultKey(null);
    await _repo.signOut();
    username = null;
    library = const [];
    offerBiometric = false;
    startOver();
  }

  /// A 401 anywhere means the session is gone: drop back to sign-in.
  void _handle(AppException e) {
    if (e.failure == Failure.signedOut) {
      unawaited(_lock.disable());
      username = null;
      library = const [];
      dataset = null;
      processingFile = null;
      authError = Failure.signedOut;
      notifyListeners();
    }
  }

  // ---- biometric lock -------------------------------------------------------

  final AppLock _lock;
  bool biometricAvailable = false;
  bool get biometricEnabled => _lock.enabled;

  /// Show the one-time "unlock with fingerprint next time?" card.
  bool offerBiometric = false;

  /// App is locked: only the lock screen is shown until the fingerprint
  /// (or a fresh password sign-in) opens it.
  bool locked = false;
  String? lockedUser;
  bool unlocking = false;
  bool lockBroken = false;

  /// Lock again after this long in the background.
  static const relockAfter = Duration(minutes: 5);
  DateTime? _backgroundedAt;

  LockPrompt get _prompt => LockPrompt(
        title: strings.zh ? '解锁 MyAnalyst' : 'Unlock MyAnalyst',
        subtitle: strings.zh ? '验证指纹以继续' : 'Confirm your fingerprint to continue',
        cancel: strings.zh ? '使用密码' : 'Use password',
      );

  Future<void> unlock() async {
    if (unlocking || !locked) return;
    unlocking = true;
    lockBroken = false;
    notifyListeners();
    try {
      final key = await _lock.unlock(_prompt);
      if (key == null) return; // cancelled: stay on the lock screen
      await _repo.setVaultKey(key);
      if (username == null) {
        username = await _repo.restoreSession();
        if (username == null) {
          // The stored sign-in expired while locked: password needed.
          await _lock.disable();
          authError = Failure.signedOut;
        } else {
          unawaited(loadLibrary());
        }
      } else {
        await _repo.restoreSession(); // reload the sealed refresh token
      }
      locked = false;
    } on LockBroken {
      // Fingerprints changed on the device: the key is gone for good.
      lockBroken = true;
      await _lock.disable();
      await _repo.signOut();
      _clearAfterLock();
    } finally {
      unlocking = false;
      notifyListeners();
    }
  }

  /// "Sign in with password instead": drops this device's sign-in.
  Future<void> usePasswordInstead() async {
    await _lock.disable();
    await _repo.signOut();
    _clearAfterLock();
    notifyListeners();
  }

  void _clearAfterLock() {
    locked = false;
    username = null;
    library = const [];
    dataset = null;
    _resetWorkspace();
  }

  /// Returns a message if it couldn't be turned on, or null on success.
  Future<String?> setBiometric(bool on) async {
    offerBiometric = false;
    try {
      if (on) {
        final key = await _lock.enable(_prompt);
        if (key == null) return null; // cancelled
        await _repo.setVaultKey(key, reseal: true);
      } else {
        await _repo.setVaultKey(null, reseal: true); // back to plain secure storage
        await _lock.disable();
      }
      return null;
    } catch (_) {
      return strings.biometricFailed;
    } finally {
      notifyListeners();
    }
  }

  void dismissBiometricOffer() {
    offerBiometric = false;
    notifyListeners();
  }

  /// Called from the app lifecycle observer.
  void onBackgrounded() => _backgroundedAt ??= _clock();

  void onForegrounded() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since == null || !_lock.enabled || !signedIn || locked) return;
    if (_clock().difference(since) >= relockAfter) {
      _repo.lockSession();
      lockedUser = username;
      locked = true;
      notifyListeners();
    }
  }

  // ---- library (my analyses) -----------------------------------------------

  List<DatasetSummary> library = const [];
  bool libraryLoading = false;
  String? openingId;

  Future<void> loadLibrary() async {
    libraryLoading = true;
    notifyListeners();
    try {
      library = await _repo.listDatasets();
    } on AppException catch (e) {
      _handle(e);
    } finally {
      libraryLoading = false;
      notifyListeners();
    }
  }

  Future<String?> openFromLibrary(String id) async {
    if (openingId != null) return null;
    openingId = id;
    notifyListeners();
    try {
      final ds = await _repo.openDataset(id, language: _lang);
      _resetWorkspace();
      dataset = ds;
      unawaited(loadRules());
      return null;
    } on AppException catch (e) {
      _handle(e);
      return strings.failure(e.failure);
    } finally {
      openingId = null;
      notifyListeners();
    }
  }

  Future<String?> deleteFromLibrary(String id) async {
    try {
      await _repo.deleteDataset(id);
      library = library.where((d) => d.id != id).toList();
      notifyListeners();
      return null;
    } on AppException catch (e) {
      _handle(e);
      return strings.failure(e.failure);
    }
  }

  // ---- dataset lifecycle ----------------------------------------------------

  Dataset? dataset;
  String? processingFile; // non-null while an upload is in flight
  String? processingError;
  /// Share of the file sent so far (0..1) while uploading; null otherwise.
  double? uploadProgress;
  _PendingUpload? _lastUpload;

  Section section = Section.overview;

  bool get isProcessing => processingFile != null && processingError == null;

  void go(Section s) {
    if (section == s) return;
    section = s;
    notifyListeners();
  }

  Future<void> openSample(SampleDataset sample) =>
      _runUpload(_PendingUpload.sample(sample), () => _repo.openSample(sample, language: _lang));

  /// Validates on-device first so obviously wrong files never leave the
  /// device. Returns the problem, or null when the file looks fine.
  FileProblem? validateFile(String name, int sizeBytes, Uint8List? head) {
    if (!name.toLowerCase().endsWith('.csv')) return FileProblem.notCsv;
    if (sizeBytes == 0) return FileProblem.empty;
    if (sizeBytes > AppConfig.maxUploadBytes) return FileProblem.tooBig;
    if (head != null && head.take(4096).contains(0)) return FileProblem.binary;
    return null;
  }

  Future<void> uploadFile(String name, Uint8List bytes) => _runUpload(
      _PendingUpload.file(name, bytes),
      () => _repo.uploadDataset(
            fileName: _safeName(name),
            bytes: bytes,
            language: _lang,
            onProgress: (p) {
              uploadProgress = p;
              notifyListeners();
            },
          ));

  Future<void> retryUpload() async {
    final last = _lastUpload;
    if (last == null) return;
    if (last.sample != null) return openSample(last.sample!);
    return uploadFile(last.name, last.bytes!);
  }

  void cancelFailedUpload() {
    processingFile = null;
    processingError = null;
    _lastUpload = null;
    notifyListeners();
  }

  Future<void> _runUpload(_PendingUpload pending, Future<Dataset> Function() run) async {
    if (isProcessing) return;
    _lastUpload = pending;
    processingFile = pending.name;
    processingError = null;
    uploadProgress = null;
    notifyListeners();
    try {
      final ds = await run();
      _resetWorkspace();
      dataset = ds;
      // Lead with cash flow when the file has it: it's what matters most.
      section = ds.cashFlow.detected && !ds.cashFlow.inflowOnly ? Section.cash : Section.overview;
      processingFile = null;
      _lastUpload = null;
      library = [DatasetSummary.of(ds), ...library.where((d) => d.id != ds.id)];
      notifyListeners();
      unawaited(loadRules());
    } on AppException catch (e) {
      processingError = strings.failure(e.failure);
      _handle(e);
      notifyListeners();
    } catch (_) {
      processingError = strings.errGeneric;
      notifyListeners();
    }
  }

  /// Strips any directory part and odd characters before the name is sent
  /// to the server or shown on screen.
  static String _safeName(String name) {
    final base = name.split(RegExp(r'[\\/]')).last;
    final clean = base.replaceAll(RegExp(r'[^\w.\- ()]'), '_');
    return clean.length > 120 ? clean.substring(clean.length - 120) : clean;
  }

  void startOver() {
    dataset = null;
    processingFile = null;
    processingError = null;
    _resetWorkspace();
    notifyListeners();
  }

  void _resetWorkspace() {
    section = Section.overview;
    rules = const [];
    rulesError = null;
    exchanges.clear();
    _sessionId = null;
    cashError = null;
  }

  // ---- cash on hand ---------------------------------------------------------

  bool cashBusy = false;
  String? cashError;

  Future<void> setCashOnHand(double amount) async {
    final ds = dataset;
    if (ds == null || cashBusy) return;
    cashBusy = true;
    cashError = null;
    notifyListeners();
    try {
      final cf = await _repo.recomputeCashFlow(ds.id, amount);
      if (dataset?.id == ds.id) dataset = ds.withCashFlow(cf);
      library = [
        for (final d in library) d.id == ds.id ? DatasetSummary.of(dataset!) : d,
      ];
    } on AppException catch (e) {
      cashError = strings.failure(e.failure);
      _handle(e);
    } finally {
      cashBusy = false;
      notifyListeners();
    }
  }

  // ---- business rules -------------------------------------------------------

  static const maxRuleLength = 2000; // matches BusinessRuleCreate in schemas.py

  List<BusinessRule> rules = const [];
  bool rulesLoading = false;
  String? rulesError;
  bool addingRule = false;

  Future<void> loadRules() async {
    final ds = dataset;
    if (ds == null) return;
    rulesLoading = true;
    rulesError = null;
    notifyListeners();
    try {
      rules = await _repo.listRules(ds.id);
    } on AppException catch (e) {
      rulesError = strings.failure(e.failure);
      _handle(e);
    } finally {
      rulesLoading = false;
      notifyListeners();
    }
  }

  /// Returns an error message, or null on success.
  Future<String?> addRule(String text) async {
    final ds = dataset;
    final t = text.trim();
    if (ds == null || addingRule) return null;
    if (t.length < 3) return strings.ruleTooShort;
    if (t.length > maxRuleLength) return strings.ruleTooLong(maxRuleLength);
    addingRule = true;
    notifyListeners();
    try {
      final rule = await _repo.addRule(ds.id, t);
      rules = [...rules, rule];
      return null;
    } on AppException catch (e) {
      _handle(e);
      return strings.failure(e.failure);
    } finally {
      addingRule = false;
      notifyListeners();
    }
  }

  // ---- questions ------------------------------------------------------------

  static const maxQuestionLength = 1000;

  final List<Exchange> exchanges = [];
  String? _sessionId;

  bool get asking => exchanges.isNotEmpty && exchanges.last.pending;

  Future<void> ask(String question) async {
    final ds = dataset;
    final q = question.trim();
    if (ds == null || q.isEmpty || asking) return;
    final ex = Exchange(question: q.length > maxQuestionLength ? q.substring(0, maxQuestionLength) : q);
    exchanges.add(ex);
    notifyListeners();
    await _resolve(ds, ex);
  }

  Future<void> retry(Exchange ex) async {
    final ds = dataset;
    if (ds == null || asking) return;
    ex.errorMessage = null;
    notifyListeners();
    await _resolve(ds, ex);
  }

  Future<void> _resolve(Dataset ds, Exchange ex) async {
    try {
      final answer = await _repo.ask(ds.id, ex.question, sessionId: _sessionId, language: _lang);
      _sessionId = answer.sessionId;
      ex.answer = answer;
    } on AppException catch (e) {
      ex.errorMessage = strings.failure(e.failure);
      _handle(e);
    } catch (_) {
      ex.errorMessage = strings.errGeneric;
    }
    notifyListeners();
  }
}

class _PendingUpload {
  _PendingUpload.sample(SampleDataset this.sample)
      : name = sample.fileName,
        bytes = null;
  _PendingUpload.file(this.name, Uint8List this.bytes) : sample = null;

  final String name;
  final Uint8List? bytes;
  final SampleDataset? sample;
}

/// Makes the controller available to the widget tree.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child})
      : super(notifier: controller);

  static AppController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Read without subscribing (for callbacks).
  static AppController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
