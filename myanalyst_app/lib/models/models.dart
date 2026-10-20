// Client-side models. Field names in fromJson mirror the backend's
// schemas.py / cashflow.py exactly; Dart names are camelCase.
//
// Parsing is deliberately defensive: the backend relays LLM output, so a
// missing or mistyped field degrades to an empty value instead of crashing
// the screen.

import 'chart_data.dart';

String _str(Object? v) => v == null ? '' : v.toString();
int _int(Object? v) => v is num ? v.toInt() : int.tryParse(_str(v)) ?? 0;
double? _dbl(Object? v) => v is num ? v.toDouble() : double.tryParse(_str(v));
List<Map<String, Object?>> _maps(Object? v) => v is List
    ? v.whereType<Map>().map((m) => m.cast<String, Object?>()).toList()
    : const [];
Map<String, Object?> _map(Object? v) =>
    v is Map ? v.cast<String, Object?>() : const {};
DateTime _date(Object? v) =>
    DateTime.tryParse(_str(v))?.toLocal() ?? DateTime.now();

class DataDictionaryEntry {
  const DataDictionaryEntry({
    required this.column,
    required this.businessMeaning,
    required this.dataType,
    this.notes = '',
  });

  final String column;
  final String businessMeaning;
  final String dataType;
  final String notes;

  factory DataDictionaryEntry.fromJson(Map<String, Object?> j) =>
      DataDictionaryEntry(
        column: _str(j['column']),
        businessMeaning: _str(j['business_meaning']),
        dataType: _str(j['data_type']),
        notes: _str(j['notes']),
      );
}

class CleaningLogEntry {
  const CleaningLogEntry(
      {required this.column, required this.action, required this.detail});

  final String column;
  final String action;
  final String detail;

  factory CleaningLogEntry.fromJson(Map<String, Object?> j) => CleaningLogEntry(
        column: _str(j['column']),
        action: _str(j['action']),
        detail: _str(j['detail']),
      );
}

// ---------------------------------------------------------------------------
// Cash flow (computed deterministically by the backend's cashflow.py)
// ---------------------------------------------------------------------------

class MonthFlow {
  const MonthFlow(this.month, this.inflow, this.outflow, this.net);
  final DateTime month;
  final double inflow, outflow, net;
}

class ProjectionPoint {
  const ProjectionPoint(this.date, this.low, this.mid, this.high);
  final DateTime date;
  final double low, mid, high;
}

class CashGap {
  const CashGap({
    required this.likely,
    required this.date,
    required this.weeksAway,
    required this.shortfall,
    required this.suggestedAmount,
  });
  final bool likely;
  final DateTime date;
  final int weeksAway;
  final double shortfall;
  final double suggestedAmount;
}

class CategoryShare {
  const CategoryShare(this.category, this.amount, this.share);
  final String category;
  final double amount, share;
}

class FinancingFit {
  const FinancingFit(
      {required this.key,
      required this.fit,
      required this.reasons,
      required this.amount,
      required this.months});
  final String key;
  final String fit; // good | possible | unlikely
  final List<String> reasons;
  final double amount;
  final int months;
}

class CashFlow {
  const CashFlow({
    required this.detected,
    this.inflowOnly = false,
    this.start,
    this.end,
    this.monthCount = 0,
    this.monthly = const [],
    this.avgIn = 0,
    this.avgOut = 0,
    this.avgNet = 0,
    this.burn = 0,
    this.trend,
    this.cashOnHand,
    this.balanceSource = 'unknown',
    this.runwayMonths,
    this.projection = const [],
    this.gap,
    this.topOut = const [],
    this.topIn = const [],
    this.financing = const [],
  });

  final bool detected;
  final bool inflowOnly;
  final DateTime? start, end;
  final int monthCount;
  final List<MonthFlow> monthly;
  final double avgIn, avgOut, avgNet, burn;
  final String? trend;
  final double? cashOnHand;
  final String balanceSource; // statement | user | unknown
  final double? runwayMonths;
  final List<ProjectionPoint> projection;
  final CashGap? gap;
  final List<CategoryShare> topOut, topIn;
  final List<FinancingFit> financing;

  static const none = CashFlow(detected: false);

  factory CashFlow.fromJson(Object? raw) {
    final j = _map(raw);
    if (j['detected'] != true) return none;
    final period = _map(j['period']);
    final g = j['cash_gap'] is Map ? _map(j['cash_gap']) : null;
    List<CategoryShare> shares(Object? v) => _maps(v)
        .map((m) => CategoryShare(
            _str(m['category']), _dbl(m['amount']) ?? 0, _dbl(m['share']) ?? 0))
        .toList();
    return CashFlow(
      detected: true,
      inflowOnly: j['mode'] == 'inflow_only',
      start: DateTime.tryParse(_str(period['start'])),
      end: DateTime.tryParse(_str(period['end'])),
      monthCount: _int(period['months']),
      monthly: _maps(j['monthly'])
          .map((m) => MonthFlow(
              DateTime.tryParse('${_str(m['month'])}-01') ?? DateTime(2000),
              _dbl(m['inflow']) ?? 0,
              _dbl(m['outflow']) ?? 0,
              _dbl(m['net']) ?? 0))
          .toList(),
      avgIn: _dbl(j['avg_monthly_inflow']) ?? 0,
      avgOut: _dbl(j['avg_monthly_outflow']) ?? 0,
      avgNet: _dbl(j['avg_monthly_net']) ?? 0,
      burn: _dbl(j['monthly_burn']) ?? 0,
      trend: j['trend'] as String?,
      cashOnHand: _dbl(j['cash_on_hand']),
      balanceSource: _str(j['balance_source']),
      runwayMonths: _dbl(j['runway_months']),
      projection: _maps(j['projection'])
          .map((p) => ProjectionPoint(
              DateTime.tryParse(_str(p['date'])) ?? DateTime(2000),
              _dbl(p['low']) ?? 0,
              _dbl(p['mid']) ?? 0,
              _dbl(p['high']) ?? 0))
          .toList(),
      gap: g == null
          ? null
          : CashGap(
              likely: g['likelihood'] == 'likely',
              date: DateTime.tryParse(_str(g['date'])) ?? DateTime(2000),
              weeksAway: _int(g['weeks_away']),
              shortfall: _dbl(g['shortfall']) ?? 0,
              suggestedAmount: _dbl(g['suggested_amount']) ?? 0,
            ),
      topOut: shares(j['top_outflows']),
      topIn: shares(j['top_inflows']),
      financing: _maps(j['financing'])
          .map((f) => FinancingFit(
                key: _str(f['key']),
                fit: _str(f['fit']),
                reasons:
                    (f['reasons'] is List ? f['reasons'] as List : const [])
                        .map(_str)
                        .toList(),
                amount: _dbl(f['amount']) ?? 0,
                months: _int(f['months']).clamp(1, 60),
              ))
          .toList(),
    );
  }
}

/// What was hidden from the LLM (backend privacy.py).
class PrivacyReport {
  const PrivacyReport({this.namesProtected = 0, this.found = const {}});
  final int namesProtected;
  final Map<String, int> found; // phone / email / id / card -> cells

  factory PrivacyReport.fromJson(Object? raw) {
    final j = _map(raw);
    final found = <String, int>{};
    _map(j['found_in_data']).forEach((k, v) => found[k] = _int(v));
    return PrivacyReport(
        namesProtected: _int(j['names_protected']), found: found);
  }
}

// ---------------------------------------------------------------------------
// Datasets
// ---------------------------------------------------------------------------

/// A full analysis: `POST /datasets/upload` or `GET /datasets/{id}`.
class Dataset {
  const Dataset({
    required this.id,
    required this.fileName,
    required this.rowCount,
    required this.columnCount,
    required this.dictionary,
    required this.cleaningLog,
    required this.charts,
    required this.executiveSummary,
    required this.uploadedAt,
    this.cashFlow = CashFlow.none,
    this.privacy = const PrivacyReport(),
  });

  final String id;
  final String fileName;
  final int rowCount;
  final int columnCount;
  final List<DataDictionaryEntry> dictionary;
  final List<CleaningLogEntry> cleaningLog;
  final List<ChartData> charts;
  final String executiveSummary;
  final DateTime uploadedAt;
  final CashFlow cashFlow;
  final PrivacyReport privacy;

  Dataset withCashFlow(CashFlow cf) => Dataset(
        id: id,
        fileName: fileName,
        rowCount: rowCount,
        columnCount: columnCount,
        dictionary: dictionary,
        cleaningLog: cleaningLog,
        charts: charts,
        executiveSummary: executiveSummary,
        uploadedAt: uploadedAt,
        cashFlow: cf,
        privacy: privacy,
      );

  factory Dataset.fromUploadJson(Map<String, Object?> j,
      {required String fileName, DateTime? uploadedAt}) {
    final serverName = _str(j['file_name']);
    final created = DateTime.tryParse(_str(j['created_at']))?.toLocal();
    return Dataset(
      id: _str(j['dataset_id']),
      fileName: serverName.isNotEmpty ? serverName : fileName,
      rowCount: _int(j['row_count']),
      columnCount: _int(j['column_count']),
      dictionary: _maps(j['data_dictionary'])
          .map(DataDictionaryEntry.fromJson)
          .toList(),
      cleaningLog:
          _maps(j['cleaning_log']).map(CleaningLogEntry.fromJson).toList(),
      charts: _maps(j['charts']).map(ChartData.fromBackendChart).toList(),
      executiveSummary: _str(j['executive_summary']),
      uploadedAt: uploadedAt ?? created ?? DateTime.now(),
      cashFlow: CashFlow.fromJson(j['cashflow']),
      privacy: PrivacyReport.fromJson(j['privacy']),
    );
  }
}

/// Reads the backend's workspace response (`GET /workspaces/{id}`, upload).
/// A workspace can hold several files; the app shows them as one analysis,
/// named after the first file, with the workspace's best cash-flow file.
Dataset datasetFromWorkspaceJson(Map<String, Object?> j,
    {String fallbackName = 'dataset.csv', DateTime? openedAt}) {
  final files = _maps(j['files']);
  final tabular = files.where((f) => f['file_type'] == 'tabular').toList();
  final first = tabular.isNotEmpty
      ? tabular.first
      : (files.isNotEmpty ? files.first : const <String, Object?>{});
  final details = _map(first['details']);
  final rows =
      tabular.fold<int>(0, (n, f) => n + _int(_map(f['details'])['rows']));
  final name = _str(j['cashflow_file']).isNotEmpty
      ? _str(j['cashflow_file'])
      : _str(first['filename']);
  return Dataset(
    id: _str(j['workspace_id']),
    fileName: name.isNotEmpty ? name : fallbackName,
    rowCount: rows > 0 ? rows : _int(details['rows']),
    columnCount: _int(details['columns']),
    dictionary:
        _maps(j['data_dictionary']).map(DataDictionaryEntry.fromJson).toList(),
    cleaningLog:
        _maps(j['cleaning_log']).map(CleaningLogEntry.fromJson).toList(),
    charts: _maps(j['charts']).map(ChartData.fromBackendChart).toList(),
    executiveSummary: _str(j['executive_summary']),
    uploadedAt: openedAt ?? DateTime.now(),
    cashFlow: CashFlow.fromJson(j['cashflow']),
    privacy: PrivacyReport.fromJson(j['privacy']),
  );
}

/// One row of `GET /datasets`.
class DatasetSummary {
  const DatasetSummary({
    required this.id,
    required this.fileName,
    required this.createdAt,
    required this.rowCount,
    required this.columnCount,
    this.runwayMonths,
    this.cashGapDate,
    this.fileCount,
  });

  final String id;
  final String fileName;
  final DateTime createdAt;
  final int rowCount;
  final int columnCount;
  final double? runwayMonths;
  final DateTime? cashGapDate;

  /// Files in the workspace, when the list response provides them.
  final int? fileCount;

  factory DatasetSummary.fromJson(Map<String, Object?> j) => DatasetSummary(
        id: _str(j['dataset_id']),
        fileName: _str(j['file_name']),
        createdAt: _date(j['created_at']),
        rowCount: _int(j['row_count']),
        columnCount: _int(j['column_count']),
        runwayMonths: _dbl(j['runway_months']),
        cashGapDate: DateTime.tryParse(_str(j['cash_gap_date'])),
      );

  /// One row of `GET /workspaces`.
  factory DatasetSummary.fromWorkspaceJson(Map<String, Object?> j) {
    final files = j['files'] is List
        ? (j['files'] as List).map(_str).toList()
        : const <String>[];
    final name = _str(j['name']);
    return DatasetSummary(
      id: _str(j['workspace_id']),
      fileName: name.isNotEmpty
          ? name
          : (files.isNotEmpty ? files.first : 'workspace'),
      createdAt: _date(j['created_at']),
      rowCount: 0, // not part of the list response
      columnCount: 0,
      fileCount: files.length,
    );
  }

  factory DatasetSummary.of(Dataset d) => DatasetSummary(
        id: d.id,
        fileName: d.fileName,
        createdAt: d.uploadedAt,
        rowCount: d.rowCount,
        columnCount: d.columnCount,
        runwayMonths: d.cashFlow.runwayMonths,
        cashGapDate: d.cashFlow.gap?.date,
      );
}

class BusinessRule {
  const BusinessRule(
      {required this.id,
      required this.datasetId,
      required this.text,
      required this.createdAt});

  final int id;
  final String datasetId;
  final String text;
  final DateTime createdAt;

  factory BusinessRule.fromJson(Map<String, Object?> j) => BusinessRule(
        id: _int(j['id']),
        datasetId: _str(j['workspace_id'] ?? j['dataset_id']),
        text: _str(j['rule_text']),
        createdAt: _date(j['created_at']),
      );
}

/// Result of `POST /datasets/{id}/qa`.
class Answer {
  const Answer({
    required this.sessionId,
    required this.text,
    required this.generatedCode,
    required this.attempts,
    this.chart,
    this.resultPreview,
    this.failed = false,
  });

  final String sessionId;
  final String text;
  final String generatedCode;
  final int attempts;
  final ChartData? chart;

  /// Short plain-text rendering of `execution_output.result`, when it's a
  /// scalar or small table. Null when a chart carries the result instead.
  final String? resultPreview;

  /// True when the agent gave up after exhausting its retries.
  final bool failed;

  /// Number of times the agent had to fix its own code before it worked.
  int get corrections => attempts > 1 ? attempts - 1 : 0;

  factory Answer.fromJson(Map<String, Object?> j) {
    final out = (j['execution_output'] is Map)
        ? (j['execution_output'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final errors = j['errors'] is List ? (j['errors'] as List) : const [];
    final plotly = out['plotly_json'];
    final chart = plotly is String && plotly.isNotEmpty
        ? ChartData.fromPlotlyJson(plotly, title: '')
        : null;
    final result = out['result'];
    final succeeded = out.isNotEmpty;
    return Answer(
      sessionId: _str(j['session_id']),
      text: _str(j['answer']),
      generatedCode: _str(j['generated_code']),
      attempts: _int(j['attempts']),
      chart: chart is UnsupportedChart ? null : chart,
      resultPreview: chart == null ? _previewResult(result) : null,
      // The backend returns 200 with an apology when it gives up; detect it so
      // the UI can style it as a failure rather than a recommendation.
      failed: !succeeded && errors.isNotEmpty,
    );
  }

  static String? _previewResult(Object? r) {
    if (r == null) return null;
    if (r is num || r is bool) return r.toString();
    if (r is String) {
      final s = r.trim();
      // A JSON-encoded figure that slipped through as `result` is not useful as text.
      if (s.isEmpty || s.startsWith('{"data"')) return null;
      return s.length > 400 ? '${s.substring(0, 400)}…' : s;
    }
    return null; // dicts/lists: the written answer already summarises them
  }
}

/// One exchange in the Ask thread (question, then answer or error).
class Exchange {
  Exchange(
      {required this.question,
      this.answer,
      this.errorMessage,
      DateTime? askedAt})
      : askedAt = askedAt ?? DateTime.now();

  final String question;
  final DateTime askedAt;
  Answer? answer;
  String? errorMessage;

  bool get pending => answer == null && errorMessage == null;
}
