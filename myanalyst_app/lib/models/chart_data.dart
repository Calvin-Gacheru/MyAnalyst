// Native chart model, plus an adapter from the Plotly figure JSON the
// backend returns (`fig.to_json()`).
//
// Why not just embed Plotly.js in a WebView? Chart titles, axis labels and
// category names come straight from the uploaded CSV and from LLM-written
// code, so they are attacker-controllable. Rendering them as plain Flutter
// text means there is no HTML/JS surface for them to exploit, and the
// charts look like part of the app instead of a web page dropped inside it.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

enum AxisKind { number, time, category }

sealed class ChartData {
  const ChartData({required this.title, this.xLabel = '', this.yLabel = '', this.note});

  final String title;
  final String xLabel;
  final String yLabel;

  /// Short provenance line shown under the chart, e.g. the forecast model.
  final String? note;

  /// Builds a chart from one element of the upload response's `charts` list:
  /// `{title, type, plotly_json}` or `{title, type, error}`.
  static ChartData fromBackendChart(Map<String, Object?> j) {
    final title = (j['title'] ?? '').toString();
    final type = (j['type'] ?? '').toString();
    final error = j['error'];
    final plotly = j['plotly_json'];
    if (error != null || plotly is! String) {
      return UnsupportedChart(title: title, reason: 'This chart could not be generated for this dataset.');
    }
    return fromPlotlyJson(plotly, title: title, typeHint: type);
  }

  static ChartData fromPlotlyJson(String json, {required String title, String typeHint = ''}) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) throw const FormatException('figure is not an object');
      return _PlotlyAdapter(decoded.cast<String, Object?>(), title, typeHint).convert();
    } catch (_) {
      return UnsupportedChart(title: title, reason: 'This chart is in a format the app can\'t display yet.');
    }
  }
}

class Bin {
  const Bin(this.label, this.value, {this.from, this.to});
  final String label;
  final double value;
  final double? from;
  final double? to;
}

/// Bar chart. Also used for histograms (pre-binned) and for pie charts,
/// which read more accurately as sorted bars.
class BarSpec extends ChartData {
  const BarSpec({
    required super.title,
    required this.bins,
    this.isHistogram = false,
    super.xLabel,
    super.yLabel,
    super.note,
  });

  final List<Bin> bins;
  final bool isHistogram;
}

class ScatterSpec extends ChartData {
  const ScatterSpec({required super.title, required this.xs, required this.ys, super.xLabel, super.yLabel, super.note});
  final List<double> xs;
  final List<double> ys;
}

class LineSeries {
  const LineSeries({required this.name, required this.xs, required this.ys, this.dashed = false});
  final String name;
  final List<double> xs; // epoch ms when the axis is time, index when category
  final List<double> ys;
  final bool dashed;
}

class Band {
  const Band({required this.xs, required this.lower, required this.upper});
  final List<double> xs;
  final List<double> lower;
  final List<double> upper;
}

class LineSpec extends ChartData {
  const LineSpec({
    required super.title,
    required this.series,
    required this.xKind,
    this.categories = const [],
    this.band,
    this.isForecast = false,
    super.xLabel,
    super.yLabel,
    super.note,
  });

  final List<LineSeries> series;
  final AxisKind xKind;
  final List<String> categories;
  final Band? band;
  final bool isForecast;

  /// x where the forecast begins: the last observed point. (Prophet's
  /// forecast line also covers the history, so its first x isn't it.)
  double? get forecastStart {
    if (!series.any((s) => s.dashed)) return null;
    double? last;
    for (final s in series.where((s) => !s.dashed && s.xs.isNotEmpty)) {
      final m = s.xs.reduce(math.max);
      if (last == null || m > last) last = m;
    }
    return last;
  }
}

class BoxGroup {
  const BoxGroup(this.label, this.min, this.q1, this.median, this.q3, this.max, this.count);
  final String label;
  final double min, q1, median, q3, max;
  final int count;
}

class BoxSpec extends ChartData {
  const BoxSpec({required super.title, required this.groups, super.xLabel, super.yLabel, super.note});
  final List<BoxGroup> groups;
}

class UnsupportedChart extends ChartData {
  const UnsupportedChart({required super.title, required this.reason});
  final String reason;
}

// ---------------------------------------------------------------------------
// Plotly adapter
// ---------------------------------------------------------------------------

class _PlotlyAdapter {
  _PlotlyAdapter(this.fig, this.fallbackTitle, this.typeHint);

  final Map<String, Object?> fig;
  final String fallbackTitle;
  final String typeHint;

  late final List<Map<String, Object?>> traces = (fig['data'] is List)
      ? (fig['data'] as List).whereType<Map>().map((t) => t.cast<String, Object?>()).toList()
      : const [];
  late final Map<String, Object?> layout =
      fig['layout'] is Map ? (fig['layout'] as Map).cast<String, Object?>() : const {};

  String get title {
    if (fallbackTitle.isNotEmpty) return fallbackTitle;
    return _titleText(layout['title']);
  }

  String get xLabel => _axisTitle('xaxis');
  String get yLabel => _axisTitle('yaxis');

  ChartData convert() {
    if (traces.isEmpty) throw const FormatException('no traces');
    final type = (traces.first['type'] ?? 'scatter').toString();
    switch (type) {
      case 'histogram':
        return _histogram(traces.first);
      case 'bar':
        return _bar(traces.first);
      case 'pie':
        return _pie(traces.first);
      case 'box':
        return _box();
      case 'scatter':
      case 'scattergl':
        return _scatterOrLine();
      default:
        throw FormatException('unsupported trace type $type');
    }
  }

  // --- histogram -----------------------------------------------------------

  ChartData _histogram(Map<String, Object?> t) {
    final raw = _values(t['x']).isNotEmpty ? _values(t['x']) : _values(t['y']);
    final nums = raw.map(_toDouble).whereType<double>().toList();
    if (nums.length < raw.length * 0.9) {
      // Categorical histogram: count occurrences.
      return BarSpec(title: title, bins: _countBins(raw), xLabel: xLabel, yLabel: 'Count');
    }
    return BarSpec(
      title: title,
      bins: histogramBins(nums),
      isHistogram: true,
      xLabel: xLabel,
      yLabel: 'Count',
    );
  }

  /// "Nice" bin widths (1, 2, 2.5, 5 × 10^k) so the edges are round numbers
  /// a reader can say out loud.
  static List<Bin> histogramBins(List<double> values, {int target = 14}) {
    if (values.isEmpty) return const [];
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    if (lo == hi) return [Bin(_fmt(lo), values.length.toDouble(), from: lo, to: hi)];

    final rough = (hi - lo) / target;
    final mag = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
    final width = [1.0, 2.0, 2.5, 5.0, 10.0].map((m) => m * mag).firstWhere((w) => w >= rough);
    final start = (lo / width).floor() * width;
    final n = ((hi - start) / width).floor() + 1;
    final counts = List<double>.filled(n, 0);
    for (final v in values) {
      counts[math.min(((v - start) / width).floor(), n - 1)]++;
    }
    return [
      for (var i = 0; i < n; i++)
        Bin(_fmt(start + i * width), counts[i], from: start + i * width, to: start + (i + 1) * width),
    ];
  }

  List<Bin> _countBins(List<Object?> raw) {
    final counts = <String, double>{};
    for (final v in raw) {
      final k = v?.toString() ?? '—';
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in sorted.take(20)) Bin(e.key, e.value)];
  }

  // --- bar / pie -----------------------------------------------------------

  ChartData _bar(Map<String, Object?> t) {
    final horizontal = t['orientation'] == 'h';
    final cats = _values(horizontal ? t['y'] : t['x']);
    final vals = _values(horizontal ? t['x'] : t['y']).map(_toDouble).toList();
    final bins = <Bin>[
      for (var i = 0; i < math.min(cats.length, vals.length); i++)
        if (vals[i] != null) Bin(_label(cats[i]), vals[i]!),
    ];
    return BarSpec(
      title: title,
      bins: bins.take(30).toList(),
      xLabel: horizontal ? yLabel : xLabel,
      yLabel: horizontal ? xLabel : yLabel,
      note: traces.length > 1 ? 'Showing the first of ${traces.length} series.' : null,
    );
  }

  ChartData _pie(Map<String, Object?> t) {
    final labels = _values(t['labels']);
    final vals = _values(t['values']).map(_toDouble).toList();
    final bins = <Bin>[
      for (var i = 0; i < math.min(labels.length, vals.length); i++)
        if (vals[i] != null) Bin(_label(labels[i]), vals[i]!),
    ]..sort((a, b) => b.value.compareTo(a.value));
    return BarSpec(title: title, bins: bins.take(20).toList(), note: 'Shown as bars for easier comparison.');
  }

  // --- box -----------------------------------------------------------------

  ChartData _box() {
    final groups = <String, List<double>>{};
    for (final t in traces.where((t) => t['type'] == 'box')) {
      final ys = _values(t['y']).map(_toDouble).toList();
      final xs = _values(t['x']);
      final traceName = (t['name'] ?? '').toString();
      for (var i = 0; i < ys.length; i++) {
        final y = ys[i];
        if (y == null) continue;
        final key = i < xs.length ? _label(xs[i]) : (traceName.isEmpty ? 'All' : traceName);
        (groups[key] ??= []).add(y);
      }
    }
    final out = groups.entries.map((e) => boxStats(e.key, e.value)).toList()
      ..sort((a, b) => b.median.compareTo(a.median));
    return BoxSpec(title: title, groups: out.take(12).toList(), xLabel: xLabel, yLabel: yLabel);
  }

  static BoxGroup boxStats(String label, List<double> values) {
    final v = [...values]..sort();
    double q(double p) {
      final pos = (v.length - 1) * p;
      final lo = pos.floor(), hi = pos.ceil();
      return v[lo] + (v[hi] - v[lo]) * (pos - lo);
    }

    return BoxGroup(label, v.first, q(.25), q(.5), q(.75), v.last, v.length);
  }

  // --- scatter / line / forecast ------------------------------------------

  ChartData _scatterOrLine() {
    final first = traces.first;
    final mode = (first['mode'] ?? '').toString();
    final isMarkersOnly = mode == 'markers' && traces.length == 1;
    final xsRaw = _values(first['x']);
    final kind = _axisKind(xsRaw);

    if (isMarkersOnly && kind == AxisKind.number) {
      final xs = <double>[], ys = <double>[];
      final ysRaw = _values(first['y']);
      for (var i = 0; i < math.min(xsRaw.length, ysRaw.length); i++) {
        final x = _toDouble(xsRaw[i]), y = _toDouble(ysRaw[i]);
        if (x != null && y != null) {
          xs.add(x);
          ys.add(y);
        }
      }
      return ScatterSpec(title: title, xs: xs, ys: ys, xLabel: xLabel, yLabel: yLabel);
    }

    // Collect every x seen so categorical axes share one index.
    final categories = <String>[];
    if (kind == AxisKind.category) {
      for (final t in traces) {
        for (final x in _values(t['x'])) {
          final s = _label(x);
          if (!categories.contains(s)) categories.add(s);
        }
      }
    }
    double? mapX(Object? x) => switch (kind) {
          AxisKind.time => _toTime(x)?.millisecondsSinceEpoch.toDouble(),
          AxisKind.number => _toDouble(x),
          AxisKind.category => categories.indexOf(_label(x)).toDouble(),
        };

    final series = <LineSeries>[];
    Band? band;
    for (var i = 0; i < traces.length; i++) {
      final t = traces[i];
      final xs = _values(t['x']), ys = _values(t['y']);
      final px = <double>[], py = <double>[];
      for (var k = 0; k < math.min(xs.length, ys.length); k++) {
        final x = mapX(xs[k]), y = _toDouble(ys[k]);
        if (x != null && y != null) {
          px.add(x);
          py.add(y);
        }
      }
      // A `fill: tonexty` trace is the lower edge of a band whose upper edge
      // is the previous trace (that's how backend forecasting.py draws it).
      if (t['fill'] == 'tonexty' && series.isNotEmpty && band == null) {
        final upper = series.removeLast();
        band = Band(xs: px, lower: py, upper: upper.ys.length == py.length ? upper.ys : py);
        continue;
      }
      final line = t['line'] is Map ? (t['line'] as Map) : const {};
      if (line['width'] == 0) {
        // Invisible upper edge; hold it until its partner arrives.
        series.add(LineSeries(name: '__band_upper', xs: px, ys: py));
        continue;
      }
      series.add(LineSeries(
        name: (t['name'] ?? '').toString(),
        xs: px,
        ys: py,
        dashed: line['dash'] != null && line['dash'] != 'solid',
      ));
    }
    series.removeWhere((s) => s.name == '__band_upper');

    final layoutTitle = _titleText(layout['title']);
    final model = RegExp(r'\(([^)]*)\)\s*$').firstMatch(layoutTitle)?.group(1)?.replaceAll(RegExp(r'\s*Model$'), '');
    final isForecast = typeHint == 'forecast' || series.any((s) => s.dashed) && band != null;

    return LineSpec(
      title: title,
      series: series,
      xKind: kind,
      categories: categories,
      band: band,
      isForecast: isForecast,
      xLabel: xLabel,
      yLabel: yLabel,
      note: isForecast && model != null ? 'Model: $model. Shaded area is the likely range.' : null,
    );
  }

  // --- value helpers -------------------------------------------------------

  AxisKind _axisKind(List<Object?> xs) {
    final sample = xs.take(20).where((x) => x != null).toList();
    if (sample.isEmpty) return AxisKind.number;
    if (sample.every((x) => x is num)) return AxisKind.number;
    if (sample.every((x) => x is String && _toTime(x) != null)) return AxisKind.time;
    if (sample.every((x) => _toDouble(x) != null)) return AxisKind.number;
    return AxisKind.category;
  }

  String _axisTitle(String axis) {
    final a = layout[axis];
    return a is Map ? _titleText(a['title']) : '';
  }

  static String _titleText(Object? t) {
    if (t is String) return t;
    if (t is Map && t['text'] is String) return t['text'] as String;
    return '';
  }

  /// Plotly ≥ 6 serialises numeric arrays as `{dtype, bdata}` (base64,
  /// little-endian). Older versions use plain JSON lists. Handle both.
  static List<Object?> _values(Object? v) {
    if (v is List) return v;
    if (v is Map && v['bdata'] is String) return _decodeTyped(v['bdata'] as String, (v['dtype'] ?? 'f8').toString());
    return const [];
  }

  static List<Object?> _decodeTyped(String b64, String dtype) {
    final bytes = base64Decode(b64);
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    const le = Endian.little;
    final (size, read) = switch (dtype) {
      'f8' => (8, (int o) => data.getFloat64(o, le)),
      'f4' => (4, (int o) => data.getFloat32(o, le)),
      'i1' => (1, (int o) => data.getInt8(o)),
      'u1' => (1, (int o) => data.getUint8(o)),
      'i2' => (2, (int o) => data.getInt16(o, le)),
      'u2' => (2, (int o) => data.getUint16(o, le)),
      'i4' => (4, (int o) => data.getInt32(o, le)),
      'u4' => (4, (int o) => data.getUint32(o, le)),
      'i8' => (8, (int o) => data.getInt64(o, le)),
      'u8' => (8, (int o) => data.getUint64(o, le)),
      _ => throw FormatException('unknown dtype $dtype'),
    };
    return [for (var o = 0; o + size <= bytes.length; o += size) read(o)];
  }

  static double? _toDouble(Object? v) {
    if (v is num) return v.isFinite ? v.toDouble() : null;
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  static DateTime? _toTime(Object? v) {
    if (v is! String || v.length < 8) return null;
    if (!RegExp(r'^\d{4}-\d{2}').hasMatch(v)) return null;
    return DateTime.tryParse(v);
  }

  static String _label(Object? v) {
    if (v is double && v == v.roundToDouble()) return v.toInt().toString();
    return v?.toString() ?? '—';
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(v.abs() < 10 ? 2 : 1);
  }
}
