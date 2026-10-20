import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../finance/financing.dart';
import '../i18n/strings.dart';
import '../models/models.dart';
import '../state/app_controller.dart';
import '../theme/tokens.dart';
import 'charts.dart' show niceRange;
import 'common.dart';

class CashFlowPage extends StatefulWidget {
  const CashFlowPage({super.key});

  @override
  State<CashFlowPage> createState() => _CashFlowPageState();
}

class _CashFlowPageState extends State<CashFlowPage> {
  final _optionsKey = GlobalKey();

  void _scrollToOptions() {
    final ctx = _optionsKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    final ds = app.dataset!;
    final cf = ds.cashFlow;

    if (!cf.detected) {
      return PageFrame(maxWidth: 820, children: [
        PageHeader(eyebrow: s.navCash, title: s.cashTitle),
        Notice(
          title: s.notDetectedTitle,
          body: s.notDetectedBody,
          tone: Palette.inkMuted,
          wash: Palette.sunken,
          icon: Icons.info_outline,
        ),
      ]);
    }

    final period = cf.start != null && cf.end != null
        ? s.cashPeriod(fmtDate(cf.start!, s.zh), fmtDate(cf.end!, s.zh), cf.monthCount)
        : null;

    return PageFrame(
      children: [
        PageHeader(eyebrow: s.navCash, title: humanizeFileName(ds.fileName), subtitle: period),
        if (cf.inflowOnly) ...[
          Notice(
            title: s.inflowOnlyTitle,
            body: s.inflowOnlyBody,
            tone: Palette.inkMuted,
            wash: Palette.sunken,
            icon: Icons.info_outline,
          ),
          const SizedBox(height: Space.lg),
          _Figures(figures: [
            (s.moneyIn, fmtMoney(cf.avgIn), s.perMonthRecent, null),
          ]),
          SectionHeading(s.monthlyInOut),
          _MonthlyBars(cf: cf),
          if (cf.topIn.isNotEmpty) ...[
            SectionHeading(s.whereMoneyComes, meta: s.last90),
            _Shares(items: cf.topIn, color: Palette.series[0]),
          ],
        ] else ...[
          _GapNotice(cf: cf, onSeeOptions: _scrollToOptions),
          const SizedBox(height: Space.lg),
          _Figures(figures: [
            (
              s.cashNow,
              cf.cashOnHand == null ? '—' : fmtMoney(cf.cashOnHand!),
              switch (cf.balanceSource) { 'statement' => s.fromStatement, 'user' => s.youEntered, _ => s.runwayUnknown },
              null,
            ),
            (
              s.runway,
              cf.runwayMonths != null
                  ? s.runwayMonths(cf.runwayMonths!.toStringAsFixed(1))
                  : (cf.burn <= 0 ? s.runwayNotBurning : '—'),
              cf.burn > 0 ? (s.zh ? '每月消耗 ${fmtMoney(cf.burn)}' : 'burning ${fmtMoney(cf.burn)} a month') : '',
              cf.runwayMonths != null && cf.runwayMonths! < 3 ? Palette.brick : null,
            ),
            (s.moneyIn, fmtMoney(cf.avgIn), s.perMonthRecent, null),
            (s.moneyOut, fmtMoney(cf.avgOut), s.perMonthRecent, null),
          ]),
          const SizedBox(height: Space.lg),
          const _CashOnHandInput(),
          if (cf.projection.isNotEmpty) ...[
            SectionHeading(s.projectionTitle),
            _Projection(cf: cf),
            const SizedBox(height: Space.sm),
            Text(s.projectionCaption, style: Txt.caption),
          ],
          SectionHeading(s.monthlyInOut),
          _MonthlyBars(cf: cf),
          if (cf.trend != null) ...[
            const SizedBox(height: Space.md),
            Row(children: [
              Icon(
                switch (cf.trend) { 'worsening' => Icons.trending_down, 'improving' => Icons.trending_up, _ => Icons.trending_flat },
                size: 18,
                color: cf.trend == 'worsening' ? Palette.brick : (cf.trend == 'improving' ? Palette.accent : Palette.inkMuted),
              ),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(
                  switch (cf.trend) { 'worsening' => s.trendWorsening, 'improving' => s.trendImproving, _ => s.trendSteady },
                  style: Txt.body,
                ),
              ),
            ]),
          ],
          LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth >= 760;
            final out = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SectionHeading(s.whereMoneyGoes, meta: s.last90),
              _Shares(items: cf.topOut, color: Palette.series[3]),
            ]);
            final inn = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SectionHeading(s.whereMoneyComes, meta: s.last90),
              _Shares(items: cf.topIn, color: Palette.series[0]),
            ]);
            return wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: out),
                    const SizedBox(width: Space.xl),
                    Expanded(child: inn),
                  ])
                : Column(children: [out, inn]);
          }),
          if (cf.financing.isNotEmpty) ...[
            SectionHeading(s.financingTitle, key: _optionsKey),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Breakpoints.readingWidth),
              child: Text(s.financingLead, style: Txt.bodyMuted),
            ),
            const SizedBox(height: Space.lg),
            for (final f in cf.financing) ...[
              _FinancingCard(fit: f),
              const SizedBox(height: Space.md),
            ],
            const SizedBox(height: Space.xs),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline, size: 15, color: Palette.inkFaint),
              const SizedBox(width: 6),
              Expanded(child: Text(s.notAdvice, style: Txt.caption)),
            ]),
          ],
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _GapNotice extends StatelessWidget {
  const _GapNotice({required this.cf, required this.onSeeOptions});
  final CashFlow cf;
  final VoidCallback onSeeOptions;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final gap = cf.gap;
    if (gap == null) {
      if (cf.cashOnHand == null) return const SizedBox.shrink();
      return Notice(
        title: s.noGapTitle,
        body: s.noGapBody,
        tone: Palette.accent,
        wash: Palette.accentWash,
        icon: Icons.check_circle_outline,
      );
    }
    return Notice(
      title: s.gapAlertTitle(gap.likely),
      body: s.gapAlertBody(fmtDate(gap.date, s.zh), gap.weeksAway, fmtMoney(gap.suggestedAmount)),
      tone: gap.likely ? Palette.brick : Palette.amber,
      wash: gap.likely ? Palette.brickWash : Palette.amberWash,
      action: cf.financing.isEmpty
          ? null
          : TextButton(
              style: TextButton.styleFrom(
                foregroundColor: gap.likely ? Palette.brick : Palette.amber,
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
              ),
              onPressed: onSeeOptions,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(s.seeOptions),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_downward, size: 15),
              ]),
            ),
    );
  }
}

/// Key figures: label, value, caption, optional value colour.
class _Figures extends StatelessWidget {
  const _Figures({required this.figures});
  final List<(String, String, String, Color?)> figures;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final perRow = box.maxWidth >= 760 ? figures.length : 2;
      final w = (box.maxWidth - (perRow - 1)) / perRow;
      return DecoratedBox(
        decoration: const BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: Palette.rule))),
        child: Wrap(children: [
          for (var i = 0; i < figures.length; i++)
            Container(
              width: w,
              decoration: BoxDecoration(
                border: Border(
                  left: i % perRow == 0 ? BorderSide.none : const BorderSide(color: Palette.rule),
                  top: i >= perRow ? const BorderSide(color: Palette.rule) : BorderSide.none,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.sm, Space.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(figures[i].$1, style: Txt.caption),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(figures[i].$2,
                      style: Txt.figure.copyWith(fontSize: perRow == 2 ? 22 : 26, color: figures[i].$4 ?? Palette.ink)),
                ),
                if (figures[i].$3.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(figures[i].$3, style: Txt.caption.copyWith(fontSize: 11.5)),
                ],
              ]),
            ),
        ]),
      );
    });
  }
}

class _CashOnHandInput extends StatefulWidget {
  const _CashOnHandInput();

  @override
  State<_CashOnHandInput> createState() => _CashOnHandInputState();
}

class _CashOnHandInputState extends State<_CashOnHandInput> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = double.tryParse(_ctrl.text.replaceAll(',', '').trim());
    if (v == null || v.abs() > 1e11) return;
    FocusScope.of(context).unfocus();
    AppScope.read(context).setCashOnHand(v);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    return Sheet(
      padding: const EdgeInsets.all(Space.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.cashOnHandLabel, style: Txt.label),
        const SizedBox(height: 2),
        Text(s.cashOnHandHelp, style: Txt.caption),
        const SizedBox(height: Space.sm),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              enabled: !app.cashBusy,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
                LengthLimitingTextInputFormatter(16),
              ],
              onSubmitted: (_) => _submit(),
              style: Txt.body.copyWith(fontSize: 15, fontFeatures: Txt.tabular),
              decoration: InputDecoration(
                isDense: true,
                hintText: app.dataset?.cashFlow.cashOnHand != null ? fmtMoney(app.dataset!.cashFlow.cashOnHand!) : '0',
                prefixText: '¥ ',
                errorText: app.cashError,
              ),
            ),
          ),
          const SizedBox(width: Space.sm),
          FilledButton(
            onPressed: app.cashBusy ? null : _submit,
            child: app.cashBusy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.white))
                : Text(s.updateCash),
          ),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Charts
// ---------------------------------------------------------------------------

const _axis = TextStyle(fontFamily: 'Plex Sans', fontSize: 11, color: Palette.inkFaint, fontFeatures: Txt.tabular);
const _tip = TextStyle(fontFamily: 'Plex Sans', fontSize: 12, color: Colors.white, height: 1.4);

class _Projection extends StatelessWidget {
  const _Projection({required this.cf});
  final CashFlow cf;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cash = cf.cashOnHand ?? 0;
    final start = cf.end ?? DateTime.now();
    // Week 0 is today's balance; then one point per projected week.
    final xs = <double>[0, for (var i = 0; i < cf.projection.length; i++) i + 1.0];
    final mid = [cash, ...cf.projection.map((p) => p.mid)];
    final low = [cash, ...cf.projection.map((p) => p.low)];
    final high = [cash, ...cf.projection.map((p) => p.high)];
    final r = niceRange(math.min(low.reduce(math.min), 0), high.reduce(math.max));
    final gapWeek = cf.gap?.weeksAway.toDouble();
    DateTime dateAt(double w) => start.add(Duration(days: (w * 7).round()));

    LineChartBarData line(List<double> ys, {Color color = Colors.transparent, double width = 0}) => LineChartBarData(
          spots: [for (var i = 0; i < xs.length; i++) FlSpot(xs[i], ys[i])],
          color: color,
          barWidth: width,
          isCurved: false,
          dotData: const FlDotData(show: false),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: Space.md, children: [
        _Legend(s.likelyPath, Palette.accent),
        _Legend(s.likelyRange, Palette.series[1].withOpacity(0.35), block: true),
      ]),
      const SizedBox(height: Space.sm),
      SizedBox(
        height: 240,
        child: LineChart(LineChartData(
          minX: 0,
          maxX: xs.last,
          minY: r.min,
          maxY: r.max,
          lineBarsData: [line(high), line(low), line(mid, color: Palette.accent, width: 2.2)],
          betweenBarsData: [BetweenBarsData(fromIndex: 0, toIndex: 1, color: Palette.series[1].withOpacity(0.18))],
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: r.step,
            getDrawingHorizontalLine: (v) => v == 0
                ? const FlLine(color: Palette.brick, strokeWidth: 1.2, dashArray: [4, 3])
                : const FlLine(color: Palette.rule, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          extraLinesData: ExtraLinesData(verticalLines: [
            if (gapWeek != null)
              VerticalLine(
                x: gapWeek,
                color: Palette.brick.withOpacity(0.6),
                strokeWidth: 1,
                dashArray: [3, 3],
                label: VerticalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  padding: const EdgeInsets.only(left: 6, top: 2),
                  style: _axis.copyWith(color: Palette.brick, fontWeight: FontWeight.w600),
                  labelResolver: (_) => fmtDay(cf.gap!.date, s.zh),
                ),
              ),
          ]),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 46,
                interval: r.step,
                getTitlesWidget: (v, meta) => SideTitleWidget(
                    axisSide: meta.axisSide, child: Text(fmtMoneyShort(v, s.zh), style: _axis)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: 4,
                getTitlesWidget: (v, meta) {
                  // fl_chart always labels the max; skip it when it would sit
                  // right next to the last regular tick.
                  if (v == meta.max && v % 4 != 0) return const SizedBox.shrink();
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(v == 0 ? s.today : fmtDay(dateAt(v), s.zh), style: _axis),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => Palette.ink,
              fitInsideHorizontally: true,
              getTooltipItems: (spots) => [
                for (final sp in spots)
                  sp.barIndex != 2
                      ? null
                      : LineTooltipItem(
                          '${sp.x == 0 ? s.today : fmtDay(dateAt(sp.x), s.zh)}\n',
                          _tip.copyWith(color: const Color(0xFFBFC7C2)),
                          children: [
                            TextSpan(text: fmtMoney(sp.y), style: _tip.copyWith(fontWeight: FontWeight.w600)),
                            TextSpan(
                              text: '\n${fmtMoney(low[sp.x.round()])} – ${fmtMoney(high[sp.x.round()])}',
                              style: _tip.copyWith(color: const Color(0xFFBFC7C2), fontSize: 11),
                            ),
                          ],
                        ),
              ],
            ),
          ),
        )),
      ),
    ]);
  }
}

class _MonthlyBars extends StatelessWidget {
  const _MonthlyBars({required this.cf});
  final CashFlow cf;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final months = cf.monthly;
    if (months.isEmpty) return const SizedBox.shrink();
    final maxV = months.map((m) => math.max(m.inflow, m.outflow)).reduce(math.max);
    final r = niceRange(0, maxV, fromZero: true);
    final every = months.length > 8 ? 2 : 1;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: Space.md, children: [
        _Legend(s.moneyIn, Palette.series[0], block: true),
        if (!cf.inflowOnly) _Legend(s.moneyOut, Palette.series[3], block: true),
      ]),
      const SizedBox(height: Space.sm),
      SizedBox(
        height: 220,
        child: LayoutBuilder(builder: (context, box) {
          final groupW = (box.maxWidth - 50) / months.length;
          final rodW = math.max(3.0, math.min(14.0, groupW * (cf.inflowOnly ? 0.6 : 0.32)));
          return BarChart(BarChartData(
            maxY: r.max,
            alignment: BarChartAlignment.spaceAround,
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: r.step,
              getDrawingHorizontalLine: (_) => const FlLine(color: Palette.rule, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: true, border: const Border(bottom: BorderSide(color: Palette.ruleStrong))),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 46,
                  interval: r.step,
                  getTitlesWidget: (v, meta) =>
                      SideTitleWidget(axisSide: meta.axisSide, child: Text(fmtMoneyShort(v, s.zh), style: _axis)),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  getTitlesWidget: (v, meta) {
                    final i = v.toInt();
                    if (i < 0 || i >= months.length || i % every != 0) return const SizedBox.shrink();
                    return SideTitleWidget(axisSide: meta.axisSide, child: Text(fmtMonth(months[i].month, s.zh), style: _axis));
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => Palette.ink,
                fitInsideHorizontally: true,
                getTooltipItem: (group, _, rod, __) {
                  final m = months[group.x];
                  final title = s.zh ? '${m.month.year}年${m.month.month}月\n' : '${fmtMonth(m.month)} ${m.month.year}\n';
                  return BarTooltipItem(title, _tip.copyWith(color: const Color(0xFFBFC7C2)), children: [
                    TextSpan(text: '${s.moneyIn} ${fmtMoney(m.inflow)}\n', style: _tip),
                    if (!cf.inflowOnly) TextSpan(text: '${s.moneyOut} ${fmtMoney(m.outflow)}\n', style: _tip),
                    if (!cf.inflowOnly)
                      TextSpan(
                        text: '${s.net} ${fmtMoney(m.net)}',
                        style: _tip.copyWith(
                            fontWeight: FontWeight.w600, color: m.net < 0 ? const Color(0xFFF2B8AC) : const Color(0xFFA9D3C3)),
                      ),
                  ]);
                },
              ),
            ),
            barGroups: [
              for (var i = 0; i < months.length; i++)
                BarChartGroupData(x: i, barsSpace: 2, barRods: [
                  BarChartRodData(
                    toY: months[i].inflow,
                    width: rodW,
                    color: Palette.series[0],
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(1.5)),
                  ),
                  if (!cf.inflowOnly)
                    BarChartRodData(
                      toY: months[i].outflow,
                      width: rodW,
                      color: Palette.series[3],
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(1.5)),
                    ),
                ]),
            ],
          ));
        }),
      ),
      if (!cf.inflowOnly) ...[
        const SizedBox(height: Space.md),
        // Net per month as a compact ledger row: easier to read than a third bar.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            Padding(
              padding: const EdgeInsets.only(right: Space.sm),
              child: Text(s.net, style: Txt.caption.copyWith(fontWeight: FontWeight.w600)),
            ),
            for (final m in months)
              Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: m.net < 0 ? Palette.brickWash : Palette.accentWash,
                  borderRadius: const BorderRadius.all(Radii.sm),
                ),
                child: Text(
                  '${fmtMonth(m.month, s.zh)} ${fmtMoneyShort(m.net, s.zh)}',
                  style: Txt.caption.copyWith(
                      color: m.net < 0 ? Palette.brick : Palette.accent, fontFeatures: Txt.tabular, fontSize: 11.5),
                ),
              ),
          ]),
        ),
      ],
    ]);
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.label, this.color, {this.block = false});
  final String label;
  final Color color;
  final bool block;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: block ? 10 : 16,
          height: block ? 10 : 2.4,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(block ? 2 : 1)),
        ),
        const SizedBox(width: 6),
        Text(label, style: Txt.caption.copyWith(color: Palette.inkMuted)),
      ]);
}

class _Shares extends StatelessWidget {
  const _Shares({required this.items, required this.color});
  final List<CategoryShare> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Text('—', style: Txt.bodyMuted);
    final maxShare = items.map((i) => i.share).reduce(math.max);
    return Column(children: [
      for (final it in items.take(6))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(it.category, style: Txt.body.copyWith(fontSize: 14), overflow: TextOverflow.ellipsis)),
              Text(fmtMoney(it.amount), style: Txt.label.copyWith(fontFeatures: Txt.tabular)),
              SizedBox(
                width: 48,
                child: Text('${(it.share * 100).round()}%',
                    textAlign: TextAlign.right, style: Txt.caption.copyWith(fontFeatures: Txt.tabular)),
              ),
            ]),
            const SizedBox(height: 5),
            LayoutBuilder(
              builder: (context, box) => Container(
                height: 6,
                width: maxShare == 0 ? 0 : box.maxWidth * it.share / maxShare,
                decoration: BoxDecoration(
                  color: it.share == maxShare ? color : color.withOpacity(0.5),
                  borderRadius: const BorderRadius.all(Radius.circular(3)),
                ),
              ),
            ),
          ]),
        ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Financing
// ---------------------------------------------------------------------------

class _FinancingCard extends StatefulWidget {
  const _FinancingCard({required this.fit});
  final FinancingFit fit;

  @override
  State<_FinancingCard> createState() => _FinancingCardState();
}

class _FinancingCardState extends State<_FinancingCard> {
  bool _open = false;
  late double _amount = widget.fit.amount > 0 ? widget.fit.amount : 100000;
  late int _months = widget.fit.months;
  double? _rate;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final f = widget.fit;
    final o = financingOption(f.key, s);
    final rate = _rate ?? o.defaultRate;
    final (fitLabel, fitColor, fitWash) = switch (f.fit) {
      'good' => (s.fitGood, Palette.accent, Palette.accentWash),
      'possible' => (s.fitPossible, Palette.amber, Palette.amberWash),
      _ => (s.fitUnlikely, Palette.inkMuted, Palette.sunken),
    };
    final faded = f.fit == 'unlikely';

    return Opacity(
      opacity: faded ? 0.72 : 1,
      child: Sheet(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            borderRadius: const BorderRadius.all(Radii.lg),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text(o.name, style: Txt.heading.copyWith(fontSize: 17))),
                  const SizedBox(width: Space.sm),
                  Pill(fitLabel, color: fitColor, background: fitWash),
                ]),
                const SizedBox(height: 6),
                Text(o.what, style: Txt.body),
                const SizedBox(height: Space.sm),
                Wrap(spacing: Space.lg, runSpacing: 4, children: [
                  _KeyVal(s.typicalCost, o.cost),
                  _KeyVal(s.speed, o.speed),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Text(
                      _open
                          ? (s.zh ? '收起' : 'Less')
                          : o.defaultRate > 0
                              ? (s.zh ? '详情和计算' : 'Details and calculator')
                              : (s.zh ? '详情' : 'Details'),
                      style: Txt.label.copyWith(color: Palette.accent)),
                  Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18, color: Palette.accent),
                ]),
              ]),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.md),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Divider(),
                      const SizedBox(height: Space.sm),
                      if (f.reasons.isNotEmpty) ...[
                        Text(s.whyThisFits, style: Txt.eyebrow),
                        const SizedBox(height: 4),
                        for (final r in f.reasons)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('·  ', style: Txt.body.copyWith(color: Palette.inkFaint)),
                              Expanded(child: Text(s.reason(r), style: Txt.body)),
                            ]),
                          ),
                        const SizedBox(height: Space.sm),
                      ],
                      _KeyVal(s.goodFor, o.goodFor, block: true),
                      const SizedBox(height: Space.xs),
                      _KeyVal(s.watchOut, o.watchOut, block: true),
                      if (o.defaultRate > 0) ...[
                        const SizedBox(height: Space.md),
                        _Calculator(
                          amount: _amount,
                          months: _months,
                          rate: rate,
                          onChanged: (a, m, r) => setState(() {
                            _amount = a;
                            _months = m;
                            _rate = r;
                          }),
                        ),
                      ],
                    ]),
                  ),
          ),
        ]),
      ),
    );
  }
}

class _KeyVal extends StatelessWidget {
  const _KeyVal(this.k, this.v, {this.block = false});
  final String k, v;
  final bool block;

  @override
  Widget build(BuildContext context) {
    if (block) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k.toUpperCase(), style: Txt.eyebrow),
        const SizedBox(height: 2),
        Text(v, style: Txt.body),
      ]);
    }
    return Text.rich(TextSpan(children: [
      TextSpan(text: '$k  ', style: Txt.caption),
      TextSpan(text: v, style: Txt.label),
    ]));
  }
}

class _Calculator extends StatelessWidget {
  const _Calculator({required this.amount, required this.months, required this.rate, required this.onChanged});
  final double amount;
  final int months;
  final double rate;
  final void Function(double amount, int months, double rate) onChanged;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final (monthly, interest) = repaymentCost(amount, rate, months);
    final pct = '${(rate * 100).toStringAsFixed(1)}%';

    Widget slider(String label, String value, double v, double min, double max, int? divisions, ValueChanged<double> cb) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, style: Txt.caption)),
            Text(value, style: Txt.label.copyWith(fontFeatures: Txt.tabular)),
          ]),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              activeTrackColor: Palette.accent,
              inactiveTrackColor: Palette.rule,
              thumbColor: Palette.accent,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Slider(value: v.clamp(min, max), min: min, max: max, divisions: divisions, onChanged: cb),
            ),
          ),
        ]);

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: const BoxDecoration(color: Palette.sunken, borderRadius: BorderRadius.all(Radii.md)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.calculator.toUpperCase(), style: Txt.eyebrow),
        const SizedBox(height: Space.sm),
        slider(s.amount, fmtMoney(amount), amount, 10000, 2000000, 199, (v) => onChanged((v / 10000).round() * 10000.0, months, rate)),
        slider(s.months, '$months', months.toDouble(), 1, 36, 35, (v) => onChanged(amount, v.round(), rate)),
        slider(s.annualRate, pct, rate * 100, 1, 24, 46, (v) => onChanged(amount, months, (v * 2).round() / 200)),
        const Divider(),
        const SizedBox(height: Space.xs),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.monthlyRepayment, style: Txt.caption),
              Text(fmtMoney(monthly), style: Txt.figure.copyWith(fontSize: 20)),
            ]),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.totalInterest, style: Txt.caption),
              Text(fmtMoney(interest), style: Txt.figure.copyWith(fontSize: 20, color: Palette.brick)),
            ]),
          ),
        ]),
        const SizedBox(height: Space.xs),
        Text(s.calcNote(pct), style: Txt.caption),
      ]),
    );
  }
}
