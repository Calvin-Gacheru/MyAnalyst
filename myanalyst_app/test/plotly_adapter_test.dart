import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myanalyst_app/models/chart_data.dart';
import 'package:myanalyst_app/models/models.dart';

Map<String, Object?> _load(String name) =>
    (jsonDecode(File('assets/mock/$name').readAsStringSync()) as Map).cast<String, Object?>();

void main() {
  group('Plotly adapter on real backend-shaped output', () {
    late Dataset coffee;
    late Dataset store;

    setUpAll(() {
      coffee = Dataset.fromUploadJson(_load('coffee_upload.json'), fileName: 'coffee_sales.csv');
      store = Dataset.fromUploadJson(_load('store_upload.json'), fileName: 'store_sales.csv');
    });

    test('every sample chart converts to a native chart', () {
      for (final c in [...coffee.charts, ...store.charts]) {
        expect(c, isNot(isA<UnsupportedChart>()), reason: c.title);
      }
    });

    test('time series parses nanosecond ISO dates', () {
      final ts = coffee.charts.firstWhere((c) => c.title == 'Daily revenue') as LineSpec;
      expect(ts.xKind, AxisKind.time);
      expect(ts.series.single.xs.length, 41);
      expect(DateTime.fromMillisecondsSinceEpoch(ts.series.single.xs.first.toInt()).day, 8);
    });

    test('forecast: observed + dashed projection + band from tonexty', () {
      final f = coffee.charts.firstWhere((c) => c.title == 'revenue forecast') as LineSpec;
      expect(f.isForecast, isTrue);
      expect(f.series.map((s) => s.dashed), [false, true]);
      expect(f.band, isNotNull);
      expect(f.band!.lower.length, f.band!.upper.length);
      // Starts at the last observed point, not the start of the fitted line.
      expect(f.forecastStart, f.series.first.xs.last);
      expect(f.note, contains('Prophet'));
    });

    test('histogram decodes base64 typed arrays and bins them', () {
      final h = coffee.charts.firstWhere((c) => c.title == 'Distribution of money') as BarSpec;
      expect(h.isHistogram, isTrue);
      expect(h.bins.fold<double>(0, (s, b) => s + b.value), 262);
    });

    test('box plot groups by category', () {
      final b = coffee.charts.whereType<BoxSpec>().single;
      expect(b.groups.map((g) => g.label).toSet(), {'card', 'cash'});
      expect(b.groups.fold<int>(0, (s, g) => s + g.count), 262);
    });

    test('scatter keeps every point', () {
      final s = store.charts.whereType<ScatterSpec>().single;
      expect(s.xs.length, store.rowCount);
    });

    test('backend chart errors become an unavailable card, not a crash', () {
      final c = ChartData.fromBackendChart({'title': 'Forecast', 'type': 'forecast', 'error': 'Traceback ...'});
      expect(c, isA<UnsupportedChart>());
      // The raw server error must not be shown to the user.
      expect((c as UnsupportedChart).reason, isNot(contains('Traceback')));
    });

    test('malformed figure JSON degrades gracefully', () {
      expect(ChartData.fromPlotlyJson('{not json', title: 'x'), isA<UnsupportedChart>());
      expect(ChartData.fromPlotlyJson('{"data": []}', title: 'x'), isA<UnsupportedChart>());
    });
  });

  group('Q&A answers', () {
    final answers = _load('answers.json');
    Answer parse(String k) => Answer.fromJson({...(answers[k] as Map).cast<String, Object?>(), 'session_id': 's'});

    test('answer with chart', () {
      final a = parse('top_products');
      expect(a.chart, isA<BarSpec>());
      expect(a.failed, isFalse);
    });

    test('self-corrected answer counts corrections', () => expect(parse('payment').corrections, 1));

    test('give-up is flagged as failed', () {
      final a = parse('giveup');
      expect(a.failed, isTrue);
      expect(a.chart, isNull);
    });
  });
}
