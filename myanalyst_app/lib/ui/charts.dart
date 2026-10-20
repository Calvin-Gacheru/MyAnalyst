import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/chart_data.dart';
import '../i18n/strings.dart';
import '../theme/tokens.dart';
import 'common.dart';

/// A chart with its title, sized for a card. All text drawn here is plain
/// Flutter text, so values from the CSV can't inject markup.
class ChartCard extends StatelessWidget {
  const ChartCard({super.key, required this.chart, this.height = 240, this.framed = true});

  final ChartData chart;
  final double height;
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (chart.title.isNotEmpty) ...[
          Text(humanize(chart.title), style: Txt.label.copyWith(fontSize: 14.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
        ],
        Text(_caption(chart, S.of(context)), style: Txt.caption),
        const SizedBox(height: Space.md),
        ChartView(chart: chart, height: height),
        if (_note(chart, S.of(context)) case final note?) ...[
          const SizedBox(height: Space.sm),
          Text(note, style: Txt.caption),
        ],
      ],
    );
    if (!framed) return body;
    return Sheet(padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.md), child: body);
  }

  static String _caption(ChartData c, S s) => switch (c) {
        BarSpec(isHistogram: true) => s.capHistogram,
        BarSpec() => s.capRanked(c.bins.length),
        ScatterSpec() => s.capPoints(fmtInt(c.xs.length)),
        LineSpec(isForecast: true) => s.capForecast,
        LineSpec() => s.capOverTime,
        BoxSpec() => s.capBox,
        UnsupportedChart() => s.capNA,
      };

  /// Model notes are produced in English by the parser; localise the known one.
  static String? _note(ChartData c, S s) {
    final note = c.note;
    if (note == null || !s.zh) return note;
    final m = RegExp(r'^Model: (.*)\. Shaded').firstMatch(note);
    return m != null ? s.modelNote(m.group(1)!) : null;
  }
}

class ChartView extends StatelessWidget {
  const ChartView({super.key, required this.chart, this.height = 240});

  final ChartData chart;
  final double height;

  @override
  Widget build(BuildContext context) {
    return switch (chart) {
      final BarSpec c when c.isHistogram => SizedBox(height: height, child: _Histogram(c)),
      final BarSpec c => _RankedBars(c),
      final ScatterSpec c => SizedBox(height: height, child: _Scatter(c)),
      final LineSpec c => _Line(c, height: height),
      final BoxSpec c => _BoxPlot(c),
      UnsupportedChart() => _Unavailable(message: S.of(context).chartUnavailable, height: math.min(height, 120)),
    };
  }
}

// ---------------------------------------------------------------------------
// Shared axis helpers
// ---------------------------------------------------------------------------

const _axisStyle = TextStyle(fontFamily: 'Plex Sans', fontSize: 11, color: Palette.inkFaint, fontFeatures: Txt.tabular);
const _tooltipStyle = TextStyle(fontFamily: 'Plex Sans', fontSize: 12, color: Colors.white, height: 1.4);

/// Round step size for about [ticks] gridlines across [range].
double niceStep(double range, {int ticks = 4}) {
  if (range <= 0 || !range.isFinite) return 1;
  final rough = range / ticks;
  final mag = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
  for (final m in [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (m * mag >= rough) return m * mag;
  }
  return 10 * mag;
}

({double min, double max, double step}) niceRange(double lo, double hi, {bool fromZero = false}) {
  if (fromZero) lo = math.min(0, lo);
  if (lo == hi) {
    hi = lo + 1;
    lo = fromZero ? lo : lo - 1;
  }
  final step = niceStep(hi - lo);
  return (min: (lo / step).floor() * step, max: (hi / step).ceil() * step, step: step);
}

FlGridData _grid(double step) => FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: step,
      getDrawingHorizontalLine: (_) => const FlLine(color: Palette.rule, strokeWidth: 1),
    );

AxisTitles _leftAxis(double step) => AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 44,
        interval: step,
        getTitlesWidget: (v, meta) {
          if (v == meta.max && meta.max != meta.min && (meta.max - meta.min) % step != 0) {
            return const SizedBox.shrink();
          }
          return SideTitleWidget(axisSide: meta.axisSide, child: Text(fmtAxis(v), style: _axisStyle));
        },
      ),
    );

const _noTitles = AxisTitles(sideTitles: SideTitles(showTitles: false));

FlBorderData get _baseline => FlBorderData(
      show: true,
      border: const Border(bottom: BorderSide(color: Palette.ruleStrong)),
    );

// ---------------------------------------------------------------------------
// Histogram (vertical, touching bins)
// ---------------------------------------------------------------------------

class _Histogram extends StatelessWidget {
  const _Histogram(this.c);
  final BarSpec c;

  @override
  Widget build(BuildContext context) {
    if (c.bins.isEmpty) return const _Unavailable();
    final maxY = c.bins.map((b) => b.value).reduce(math.max);
    final r = niceRange(0, maxY, fromZero: true);
    final labelEvery = math.max(1, (c.bins.length / 6).ceil());

    return LayoutBuilder(builder: (context, box) {
      final barWidth = math.max(2.0, (box.maxWidth - 52) / c.bins.length - 2);
      return BarChart(
        BarChartData(
          minY: 0,
          maxY: r.max,
          alignment: BarChartAlignment.spaceBetween,
          gridData: _grid(r.step),
          borderData: _baseline,
          titlesData: FlTitlesData(
            leftTitles: _leftAxis(r.step),
            rightTitles: _noTitles,
            topTitles: _noTitles,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i % labelEvery != 0 || i >= c.bins.length) return const SizedBox.shrink();
                  return SideTitleWidget(axisSide: meta.axisSide, child: Text(c.bins[i].label, style: _axisStyle));
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => Palette.ink,
              tooltipRoundedRadius: 4,
              getTooltipItem: (group, _, rod, __) {
                final b = c.bins[group.x];
                final range = b.from != null ? '${fmtValue(b.from!)} – ${fmtValue(b.to!)}' : b.label;
                return BarTooltipItem('$range\n', _tooltipStyle.copyWith(color: const Color(0xFFBFC7C2)), children: [
                  TextSpan(text: S.of(context).zh ? '${fmtInt(b.value)} 行' : '${fmtInt(b.value)} rows', style: _tooltipStyle.copyWith(fontWeight: FontWeight.w600)),
                ]);
              },
            ),
          ),
          barGroups: [
            for (var i = 0; i < c.bins.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: c.bins[i].value,
                  width: barWidth,
                  color: Palette.series[0],
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(1.5)),
                ),
              ]),
          ],
        ),
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Ranked horizontal bars (category counts, pies, Q&A bar charts)
// ---------------------------------------------------------------------------

class _RankedBars extends StatefulWidget {
  const _RankedBars(this.c);
  final BarSpec c;

  @override
  State<_RankedBars> createState() => _RankedBarsState();
}

class _RankedBarsState extends State<_RankedBars> {
  static const _initial = 8;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final bins = widget.c.bins;
    if (bins.isEmpty) return const _Unavailable();
    final maxV = bins.map((b) => b.value.abs()).reduce(math.max);
    final shown = _all ? bins : bins.take(_initial).toList();
    final compact = isCompact(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < shown.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: compact ? 112 : 168,
                  child: Text(shown[i].label,
                      style: Txt.body.copyWith(fontSize: 13.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 14,
                        width: maxV == 0 ? 0 : math.max(2, box.maxWidth * shown[i].value.abs() / maxV),
                        decoration: BoxDecoration(
                          color: i == 0 ? Palette.series[0] : Palette.series[0].withOpacity(0.55),
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Space.sm),
                SizedBox(
                  width: 64,
                  child: Text(fmtValue(shown[i].value),
                      textAlign: TextAlign.right, style: Txt.label.copyWith(fontFeatures: Txt.tabular)),
                ),
              ],
            ),
          ),
        if (bins.length > _initial)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: TextButton(
              onPressed: () => setState(() => _all = !_all),
              child: Text(_all ? S.of(context).showTop(_initial) : S.of(context).showAll(bins.length)),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Scatter
// ---------------------------------------------------------------------------

class _Scatter extends StatelessWidget {
  const _Scatter(this.c);
  final ScatterSpec c;

  @override
  Widget build(BuildContext context) {
    if (c.xs.isEmpty) return const _Unavailable();
    // Thousands of dots render as a blob anyway; sample evenly for speed.
    final stride = math.max(1, (c.xs.length / 1500).ceil());
    final idx = [for (var i = 0; i < c.xs.length; i += stride) i];
    final rx = niceRange(c.xs.reduce(math.min), c.xs.reduce(math.max));
    final ry = niceRange(c.ys.reduce(math.min), c.ys.reduce(math.max));

    return ScatterChart(
      ScatterChartData(
        minX: rx.min,
        maxX: rx.max,
        minY: ry.min,
        maxY: ry.max,
        gridData: _grid(ry.step),
        borderData: _baseline,
        titlesData: FlTitlesData(
          leftTitles: _leftAxis(ry.step),
          rightTitles: _noTitles,
          topTitles: _noTitles,
          bottomTitles: AxisTitles(
            axisNameWidget: c.xLabel.isEmpty ? null : Text(humanize(c.xLabel), style: _axisStyle),
            axisNameSize: c.xLabel.isEmpty ? 0 : 18,
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: rx.step,
              getTitlesWidget: (v, meta) =>
                  SideTitleWidget(axisSide: meta.axisSide, child: Text(fmtAxis(v), style: _axisStyle)),
            ),
          ),
        ),
        scatterSpots: [
          for (final i in idx)
            ScatterSpot(c.xs[i], c.ys[i],
                dotPainter: FlDotCirclePainter(radius: 2.6, color: Palette.series[0].withOpacity(0.45), strokeWidth: 0)),
        ],
        scatterTouchData: ScatterTouchData(
          touchTooltipData: ScatterTouchTooltipData(
            getTooltipColor: (_) => Palette.ink,
            getTooltipItems: (s) => ScatterTooltipItem(
              '${humanize(c.xLabel)} ${fmtValue(s.x)}\n${humanize(c.yLabel)} ${fmtValue(s.y)}',
              textStyle: _tooltipStyle,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Line / time series / forecast
// ---------------------------------------------------------------------------

class _Line extends StatelessWidget {
  const _Line(this.c, {required this.height});
  final LineSpec c;
  final double height;

  String _xLabel(double v) => switch (c.xKind) {
        AxisKind.time => fmtDay(DateTime.fromMillisecondsSinceEpoch(v.round())),
        AxisKind.category => (v.round() >= 0 && v.round() < c.categories.length) ? c.categories[v.round()] : '',
        AxisKind.number => fmtAxis(v),
      };

  @override
  Widget build(BuildContext context) {
    final str = S.of(context);
    final start = c.isForecast ? c.forecastStart : null;

    // In a forecast, the model's fitted line over the history is noise to a
    // reader; show the projection only from the last recorded point onward.
    List<(List<double>, List<double>)> clip(List<double> xs, List<double> ys) {
      if (start == null) return [(xs, ys)];
      final px = <double>[], py = <double>[];
      for (var i = 0; i < xs.length; i++) {
        if (xs[i] >= start) {
          px.add(xs[i]);
          py.add(ys[i]);
        }
      }
      return [(px, py)];
    }

    final bars = <LineChartBarData>[];
    final legend = <(String, Color, bool)>[];
    var colorIdx = 0;
    for (final s in c.series) {
      final (xs, ys) = s.dashed ? clip(s.xs, s.ys).first : (s.xs, s.ys);
      if (xs.isEmpty) continue;
      final color = s.dashed ? Palette.series[1] : Palette.series[colorIdx++ % Palette.series.length];
      bars.add(LineChartBarData(
        spots: [for (var i = 0; i < xs.length; i++) FlSpot(xs[i], ys[i])],
        color: color,
        barWidth: s.dashed ? 2 : 1.8,
        dashArray: s.dashed ? [6, 4] : null,
        isCurved: false,
        dotData: const FlDotData(show: false),
      ));
      final name = s.name.isNotEmpty ? s.name : humanize(c.yLabel);
      legend.add((name == 'Observed' ? str.recorded : (name == 'Forecast' ? str.projection : name), color, s.dashed));
    }

    // Band: two invisible lines with the area between them filled.
    final betweens = <BetweenBarsData>[];
    if (c.band != null) {
      final b = c.band!;
      // Money and counts can't go below zero; don't let the band suggest they might.
      final nonNegative = c.series.where((s) => !s.dashed).every((s) => s.ys.every((y) => y >= 0));
      double floor(double y) => nonNegative && y < 0 ? 0 : y;
      final upper = <FlSpot>[], lower = <FlSpot>[];
      for (var i = 0; i < b.xs.length; i++) {
        if (start != null && b.xs[i] < start) continue;
        upper.add(FlSpot(b.xs[i], b.upper[i]));
        lower.add(FlSpot(b.xs[i], floor(b.lower[i])));
      }
      if (upper.isNotEmpty) {
        final ui = bars.length;
        bars.add(LineChartBarData(spots: upper, color: Colors.transparent, barWidth: 0, dotData: const FlDotData(show: false)));
        bars.add(LineChartBarData(spots: lower, color: Colors.transparent, barWidth: 0, dotData: const FlDotData(show: false)));
        betweens.add(BetweenBarsData(fromIndex: ui, toIndex: ui + 1, color: Palette.series[1].withOpacity(0.16)));
        legend.add((str.likelyRange, Palette.series[1].withOpacity(0.3), false));
      }
    }

    if (bars.isEmpty) return _Unavailable(height: height);
    final visibleCount = bars.length - (betweens.isEmpty ? 0 : 2);

    final allX = bars.expand((b) => b.spots).map((s) => s.x);
    final allY = bars.expand((b) => b.spots).map((s) => s.y);
    final minX = allX.reduce(math.min), maxX = allX.reduce(math.max);
    final ry = niceRange(allY.reduce(math.min), allY.reduce(math.max));
    final xInterval = c.xKind == AxisKind.category
        ? math.max(1, (c.categories.length / 6).ceil()).toDouble()
        : math.max((maxX - minX) / 4, 1e-9);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (legend.length > 1) ...[
          Wrap(spacing: Space.md, runSpacing: Space.xxs, children: [
            for (final (name, color, dashed) in legend) _LegendItem(name, color, dashed: dashed),
          ]),
          const SizedBox(height: Space.sm),
        ],
        SizedBox(
          height: height,
          child: LineChart(
            LineChartData(
              minX: minX,
              maxX: maxX,
              minY: ry.min,
              maxY: ry.max,
              lineBarsData: bars,
              betweenBarsData: betweens,
              gridData: _grid(ry.step),
              borderData: _baseline,
              extraLinesData: ExtraLinesData(verticalLines: [
                if (start != null)
                  VerticalLine(
                    x: start,
                    color: Palette.ruleStrong,
                    strokeWidth: 1,
                    dashArray: [3, 3],
                    label: VerticalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      padding: const EdgeInsets.only(left: 6, top: 2),
                      style: _axisStyle.copyWith(color: Palette.inkMuted),
                      labelResolver: (_) => str.projection,
                    ),
                  ),
              ]),
              titlesData: FlTitlesData(
                leftTitles: _leftAxis(ry.step),
                rightTitles: _noTitles,
                topTitles: _noTitles,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: xInterval,
                    getTitlesWidget: (v, meta) {
                      // Skip the auto-added max label when it would crowd the last tick.
                      if (v == meta.max && (meta.max - meta.min) % xInterval > xInterval * 0.01) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(axisSide: meta.axisSide, child: Text(_xLabel(v), style: _axisStyle));
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => Palette.ink,
                  tooltipRoundedRadius: 4,
                  fitInsideHorizontally: true,
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      s.barIndex >= visibleCount
                          ? null
                          : LineTooltipItem(
                              s == spots.first ? '${_xLabel(s.x)}\n' : '',
                              _tooltipStyle.copyWith(color: const Color(0xFFBFC7C2)),
                              children: [
                                TextSpan(
                                    text: '${legend[s.barIndex].$1}: ${fmtValue(s.y)}',
                                    style: _tooltipStyle.copyWith(fontWeight: FontWeight.w600)),
                              ],
                            ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem(this.label, this.color, {this.dashed = false});
  final String label;
  final Color color;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      CustomPaint(size: const Size(18, 10), painter: _SwatchPainter(color, dashed)),
      const SizedBox(width: 6),
      Text(label, style: Txt.caption.copyWith(color: Palette.inkMuted)),
    ]);
  }
}

class _SwatchPainter extends CustomPainter {
  _SwatchPainter(this.color, this.dashed);
  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    if (color.opacity < 0.5) {
      canvas.drawRect(Rect.fromLTWH(0, 1, size.width, size.height - 2), Paint()..color = color);
      return;
    }
    final p = Paint()
      ..color = color
      ..strokeWidth = 2;
    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    } else {
      for (double x = 0; x < size.width; x += 7) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, size.width), y), p);
      }
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter old) => old.color != color || old.dashed != dashed;
}

// ---------------------------------------------------------------------------
// Box plot (horizontal, one row per group, shared scale)
// ---------------------------------------------------------------------------

class _BoxPlot extends StatelessWidget {
  const _BoxPlot(this.c);
  final BoxSpec c;

  @override
  Widget build(BuildContext context) {
    if (c.groups.isEmpty) return const _Unavailable();
    final r = niceRange(c.groups.map((g) => g.min).reduce(math.min), c.groups.map((g) => g.max).reduce(math.max));
    final labelWidth = isCompact(context) ? 96.0 : 140.0;
    const rowH = 30.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final g in c.groups)
          Tooltip(
            message: '${g.label}: median ${fmtValue(g.median)}, middle half ${fmtValue(g.q1)}–${fmtValue(g.q3)}, '
                'range ${fmtValue(g.min)}–${fmtValue(g.max)} (${fmtInt(g.count)} rows)',
            child: SizedBox(
              height: rowH,
              child: Row(children: [
                SizedBox(
                  width: labelWidth,
                  child: Text(g.label, style: Txt.body.copyWith(fontSize: 13.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Expanded(child: CustomPaint(size: const Size.fromHeight(rowH), painter: _BoxPainter(g, r.min, r.max))),
                SizedBox(
                  width: 56,
                  child: Text(fmtValue(g.median),
                      textAlign: TextAlign.right, style: Txt.label.copyWith(fontFeatures: Txt.tabular)),
                ),
              ]),
            ),
          ),
        const SizedBox(height: Space.xs),
        Row(children: [
          SizedBox(width: labelWidth),
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              final ticks = <double>[for (var v = r.min; v <= r.max + r.step / 2; v += r.step) v];
              return SizedBox(
                height: 16,
                child: Stack(clipBehavior: Clip.none, children: [
                  for (final t in ticks)
                    Positioned(
                      left: (t - r.min) / (r.max - r.min) * box.maxWidth - 20,
                      width: 40,
                      child: Text(fmtAxis(t), textAlign: TextAlign.center, style: _axisStyle),
                    ),
                ]),
              );
            }),
          ),
          const SizedBox(width: 56),
        ]),
        const SizedBox(height: Space.xs),
        Text(S.of(context).boxHelp,
            style: Txt.caption),
      ],
    );
  }
}

class _BoxPainter extends CustomPainter {
  _BoxPainter(this.g, this.lo, this.hi);
  final BoxGroup g;
  final double lo, hi;

  @override
  void paint(Canvas canvas, Size size) {
    double x(double v) => hi == lo ? 0 : (v - lo) / (hi - lo) * size.width;
    final cy = size.height / 2;
    final line = Paint()
      ..color = Palette.inkMuted
      ..strokeWidth = 1;
    // Whiskers
    canvas.drawLine(Offset(x(g.min), cy), Offset(x(g.q1), cy), line);
    canvas.drawLine(Offset(x(g.q3), cy), Offset(x(g.max), cy), line);
    canvas.drawLine(Offset(x(g.min), cy - 4), Offset(x(g.min), cy + 4), line);
    canvas.drawLine(Offset(x(g.max), cy - 4), Offset(x(g.max), cy + 4), line);
    // Box
    final rect = Rect.fromLTRB(x(g.q1), cy - 8, math.max(x(g.q3), x(g.q1) + 1), cy + 8);
    canvas.drawRect(rect, Paint()..color = Palette.accentWash);
    canvas.drawRect(
        rect,
        Paint()
          ..color = Palette.series[0]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    // Median
    canvas.drawLine(
        Offset(x(g.median), cy - 8),
        Offset(x(g.median), cy + 8),
        Paint()
          ..color = Palette.series[0]
          ..strokeWidth = 2.2);
  }

  @override
  bool shouldRepaint(_BoxPainter old) => old.g != g || old.lo != lo || old.hi != hi;
}

// ---------------------------------------------------------------------------

class _Unavailable extends StatelessWidget {
  const _Unavailable({this.message, this.height = 120});
  final String? message;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: Palette.sunken, borderRadius: BorderRadius.all(Radii.md)),
      padding: const EdgeInsets.all(Space.md),
      child: Text(message ?? S.of(context).noValues, style: Txt.bodyMuted, textAlign: TextAlign.center),
    );
  }
}
