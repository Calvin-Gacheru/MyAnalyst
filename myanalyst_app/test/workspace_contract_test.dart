// Contract test: a real response from the rag-feature backend
// (POST /workspaces/new/files with bakery_transactions.csv, LLM stubbed),
// captured into test/fixtures, parsed by the app's model code.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myanalyst_app/models/chart_data.dart';
import 'package:myanalyst_app/models/models.dart';

void main() {
  final json = (jsonDecode(File('test/fixtures/workspace_bakery.json').readAsStringSync()) as Map).cast<String, Object?>();

  test('workspace response maps onto the app dataset', () {
    final ds = datasetFromWorkspaceJson(json);
    expect(ds.id, json['workspace_id']);
    expect(ds.fileName, 'bakery_transactions.csv');
    expect(ds.rowCount, 1305);
    expect(ds.columnCount, 6);
    expect(ds.dictionary, hasLength(6));
    expect(ds.cleaningLog.any((e) => e.action == 'flag_outliers_iqr'), isTrue);
    expect(ds.charts.every((c) => c is! UnsupportedChart), isTrue, reason: 'every backend chart renders natively');
  });

  test('cash flow from the backend drives the cash page', () {
    final cf = datasetFromWorkspaceJson(json).cashFlow;
    expect(cf.detected, isTrue);
    expect(cf.inflowOnly, isFalse);
    expect(cf.runwayMonths, 1.4);
    expect(cf.gap!.date, DateTime(2026, 12, 12));
    expect(cf.gap!.suggestedAmount, 200000);
    expect(cf.monthly, hasLength(12));
    expect(cf.projection, hasLength(13));
    expect(cf.financing.map((f) => f.key), containsAll(['bank_loan', 'supplier_credit', 'cost_actions']));
  });

  test('privacy report reaches the app', () {
    final p = datasetFromWorkspaceJson(json).privacy;
    expect(p.namesProtected, 18);
    expect(p.found['phone'], 3);
  });

  test('model Markdown is stripped to plain text', () {
    expect(plainText('**Cash is falling.** See `net`.\n## Next\n- cut costs\n* sell more'),
        'Cash is falling. See net.\nNext\n• cut costs\n• sell more');
    expect(plainText(null), '');
  });

  test('workspace list row', () {
    final row = DatasetSummary.fromWorkspaceJson({
      'workspace_id': json['workspace_id'],
      'name': 'bakery_transactions.csv',
      'created_at': '2026-10-20T08:00:00Z',
      'files': ['bakery_transactions.csv', 'policy.pdf'],
    });
    expect(row.fileName, 'bakery_transactions.csv');
    expect(row.fileCount, 2);
  });
}
