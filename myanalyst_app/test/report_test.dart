import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myanalyst_app/finance/financing.dart';
import 'package:myanalyst_app/i18n/strings.dart';
import 'package:myanalyst_app/models/models.dart';
import 'package:myanalyst_app/report/pdf_report.dart';

Dataset _bakery({bool zh = false}) {
  final j = (jsonDecode(File('assets/mock/bakery_upload.json').readAsStringSync()) as Map).cast<String, Object?>();
  if (zh) j['executive_summary'] = j['executive_summary_zh'];
  return Dataset.fromUploadJson(j, fileName: 'bakery_transactions.csv');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final lang in AppLanguage.values) {
    test('PDF report builds in ${lang.name}', () async {
      final bytes = await buildReport(_bakery(zh: lang == AppLanguage.zh), S(lang), preparedFor: 'li.wei');
      expect(utf8.decode(bytes.sublist(0, 5), allowMalformed: true), '%PDF-');
      expect(bytes.length, greaterThan(20000));
      // Keep a copy for manual review.
      Directory('build/reports').createSync(recursive: true);
      File('build/reports/bakery_${lang.name}.pdf').writeAsBytesSync(bytes);
    });
  }

  test('cash flow parses runway, gap and financing fit', () {
    final cf = _bakery().cashFlow;
    expect(cf.detected, isTrue);
    expect(cf.runwayMonths, 1.4);
    expect(cf.gap!.likely, isTrue);
    expect(cf.gap!.suggestedAmount, 200000);
    expect(cf.monthly, hasLength(12));
    expect(cf.financing.where((f) => f.fit == 'good').map((f) => f.key),
        containsAll(['cost_actions', 'supplier_credit', 'bank_loan']));
  });

  test('loan calculator matches the annuity formula', () {
    final (monthly, interest) = repaymentCost(200000, 0.045, 12);
    expect(monthly, closeTo(17075.70, 0.01));
    expect(interest, closeTo(4908.45, 0.01));
    expect(repaymentCost(120000, 0, 4), (30000.0, 0.0));
  });
}
