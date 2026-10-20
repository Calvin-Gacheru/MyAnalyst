// Lender-ready PDF report, generated on the device from the analysis the
// app already has. No extra data is sent anywhere to produce it.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../finance/financing.dart';
import '../i18n/strings.dart';
import '../models/models.dart';
import '../ui/common.dart' show fmtDate, fmtMoney, fmtMonth, humanizeFileName;

const _ink = PdfColor.fromInt(0xFF1C1B19);
const _muted = PdfColor.fromInt(0xFF5C5952);
const _faint = PdfColor.fromInt(0xFF8B877E);
const _rule = PdfColor.fromInt(0xFFE1DDD3);
const _accent = PdfColor.fromInt(0xFF1F5C4A);
const _accentWash = PdfColor.fromInt(0xFFE2ECE7);
const _brick = PdfColor.fromInt(0xFF9E3A2B);
const _brickWash = PdfColor.fromInt(0xFFF5E3DE);
const _out = PdfColor.fromInt(0xFFB0573A);

Future<pw.Font> _font(String path) async => pw.Font.ttf(await rootBundle.load(path));

Future<Uint8List> buildReport(Dataset ds, S s, {String? preparedFor}) async {
  final regular = await _font('assets/fonts/IBMPlexSans-Regular.ttf');
  final bold = await _font('assets/fonts/IBMPlexSans-SemiBold.ttf');
  final serif = await _font('assets/fonts/IBMPlexSerif-Regular.ttf');
  final cjk = await _font('assets/fonts/NotoSansSC-Regular-subset.ttf');
  final theme = pw.ThemeData.withFont(base: regular, bold: bold, fontFallback: [cjk]);

  final zh = s.zh;
  final cf = ds.cashFlow;
  final now = DateTime.now();
  final title = humanizeFileName(ds.fileName);

  pw.TextStyle st(double size, {PdfColor color = _ink, bool b = false, bool serifFace = false}) => pw.TextStyle(
        fontSize: size,
        color: color,
        font: serifFace ? serif : (b ? bold : regular),
        fontFallback: [cjk],
        lineSpacing: size * 0.35,
      );

  pw.Widget heading(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 18, bottom: 6),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(text, style: st(13, serifFace: true)),
          pw.SizedBox(height: 4),
          pw.Container(height: 0.6, color: _rule),
        ]),
      );

  pw.Widget figure(String label, String value, {PdfColor color = _ink, String? sub}) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.fromLTRB(8, 8, 6, 8),
          decoration: const pw.BoxDecoration(border: pw.Border(left: pw.BorderSide(color: _rule, width: 0.6))),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(label, style: st(7.5, color: _faint)),
            pw.SizedBox(height: 3),
            pw.Text(value, style: st(13, color: color, b: true)),
            if (sub != null) pw.Text(sub, style: st(7, color: _faint)),
          ]),
        ),
      );

  final paragraphs = ds.executiveSummary.split(RegExp(r'\n\s*\n')).map((p) => p.trim()).where((p) => p.isNotEmpty);

  final doc = pw.Document(
    title: '${zh ? '现金流报告' : 'Cash-flow report'} - $title',
    author: 'MyAnalyst',
    creator: 'MyAnalyst',
    theme: theme,
  );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(44, 40, 44, 44),
    header: (ctx) => ctx.pageNumber == 1
        ? pw.SizedBox()
        : pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 10),
            child: pw.Text('MyAnalyst · $title', style: st(7.5, color: _faint)),
          ),
    footer: (ctx) => pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _rule, width: 0.6))),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Text(
            zh
                ? '由 MyAnalyst 根据上传数据自动计算，未经审计。仅供参考，不构成金融建议。'
                : 'Computed automatically by MyAnalyst from the uploaded data. Not audited. For information only, not financial advice.',
            style: st(6.5, color: _faint),
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}', style: st(7, color: _faint)),
      ]),
    ),
    build: (ctx) => [
      // ---- title block -----------------------------------------------------
      pw.Row(children: [
        pw.Container(width: 3, height: 6, color: _accent),
        pw.SizedBox(width: 2.5),
        pw.Container(width: 3, height: 10, color: _accent),
        pw.SizedBox(width: 2.5),
        pw.Container(width: 3, height: 14, color: _accent),
        pw.SizedBox(width: 7),
        pw.Text('MyAnalyst', style: st(11, serifFace: true)),
      ], crossAxisAlignment: pw.CrossAxisAlignment.end),
      pw.SizedBox(height: 18),
      pw.Text(zh ? '现金流与经营报告' : 'Cash-flow and business report', style: st(9, color: _muted)),
      pw.SizedBox(height: 2),
      pw.Text(title, style: st(22, serifFace: true)),
      pw.SizedBox(height: 4),
      pw.Text(
        [
          if (cf.start != null && cf.end != null) '${fmtDate(cf.start!, zh)} – ${fmtDate(cf.end!, zh)}',
          '${zh ? '生成于' : 'Prepared'} ${fmtDate(now, zh)}',
          if (preparedFor != null) '${zh ? '账户' : 'Account'}: $preparedFor',
          '${ds.rowCount} ${zh ? '笔记录' : 'records'}',
        ].join('   ·   '),
        style: st(8, color: _faint),
      ),
      pw.SizedBox(height: 16),

      // ---- key figures -----------------------------------------------------
      if (cf.detected && !cf.inflowOnly) ...[
        pw.Container(
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: _rule, width: 0.6), bottom: pw.BorderSide(color: _rule, width: 0.6)),
          ),
          child: pw.Row(children: [
            figure(s.cashNow, cf.cashOnHand == null ? '—' : fmtMoney(cf.cashOnHand!)),
            figure(s.runway, cf.runwayMonths == null ? (cf.burn <= 0 ? s.runwayNotBurning : '—') : s.runwayMonths(cf.runwayMonths!.toStringAsFixed(1)),
                color: (cf.runwayMonths ?? 99) < 3 ? _brick : _ink),
            figure(s.moneyIn, fmtMoney(cf.avgIn), sub: s.perMonthRecent),
            figure(s.moneyOut, fmtMoney(cf.avgOut), sub: s.perMonthRecent),
            figure(s.net, fmtMoney(cf.avgNet), color: cf.avgNet < 0 ? _brick : _accent, sub: s.perMonthRecent),
          ]),
        ),
        if (cf.gap != null) ...[
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(9),
            decoration: const pw.BoxDecoration(
              color: _brickWash,
              border: pw.Border(left: pw.BorderSide(color: _brick, width: 2.5)),
            ),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(s.gapAlertTitle(cf.gap!.likely), style: st(9.5, color: _brick, b: true)),
              pw.SizedBox(height: 2),
              pw.Text(s.gapAlertBody(fmtDate(cf.gap!.date, zh), cf.gap!.weeksAway, fmtMoney(cf.gap!.suggestedAmount)),
                  style: st(8.5)),
            ]),
          ),
        ],
      ],

      // ---- summary ---------------------------------------------------------
      heading(s.whatDataSays),
      for (final p in paragraphs)
        pw.Padding(padding: const pw.EdgeInsets.only(bottom: 6), child: pw.Text(p, style: st(9.5, serifFace: !zh))),

      // ---- monthly table ---------------------------------------------------
      if (cf.detected && cf.monthly.isNotEmpty) ...[
        heading(s.monthlyInOut),
        _monthlyTable(cf, s, st),
      ],

      // ---- projection ------------------------------------------------------
      if (cf.projection.isNotEmpty) ...[
        heading(s.projectionTitle),
        pw.Text(s.projectionCaption, style: st(7.5, color: _faint)),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: [zh ? '日期' : 'Week ending', zh ? '较差情况' : 'Weaker case', s.likelyPath, zh ? '较好情况' : 'Stronger case'],
          data: [
            for (var i = 1; i < cf.projection.length; i += 2)
              [
                fmtDate(cf.projection[i].date, zh),
                fmtMoney(cf.projection[i].low),
                fmtMoney(cf.projection[i].mid),
                fmtMoney(cf.projection[i].high),
              ],
          ],
          headerStyle: st(7.5, color: _muted, b: true),
          cellStyle: st(8),
          headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEFECE5)),
          cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
          border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _rule, width: 0.4)),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
        ),
      ],

      // ---- where the money goes -------------------------------------------
      if (cf.topOut.isNotEmpty) ...[
        heading('${s.whereMoneyGoes} (${s.last90})'),
        _shares(cf.topOut, st, _out),
      ],
      if (cf.topIn.isNotEmpty) ...[
        heading('${s.whereMoneyComes} (${s.last90})'),
        _shares(cf.topIn, st, _accent),
      ],

      // ---- financing -------------------------------------------------------
      if (cf.financing.isNotEmpty) ...[
        heading(s.financingTitle),
        for (final f in cf.financing)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 5),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Container(
                width: 62,
                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                decoration: pw.BoxDecoration(
                  color: f.fit == 'good' ? _accentWash : const PdfColor.fromInt(0xFFEFECE5),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
                ),
                child: pw.Text(
                  switch (f.fit) { 'good' => s.fitGood, 'possible' => s.fitPossible, _ => s.fitUnlikely },
                  style: st(7, color: f.fit == 'good' ? _accent : _muted, b: true),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(financingOption(f.key, s).name, style: st(9, b: true)),
                  pw.Text('${s.typicalCost}: ${financingOption(f.key, s).cost}   ·   ${s.speed}: ${financingOption(f.key, s).speed}',
                      style: st(7.5, color: _muted)),
                ]),
              ),
            ]),
          ),
        pw.SizedBox(height: 2),
        pw.Text(s.notAdvice, style: st(7, color: _faint)),
      ],

      // ---- data and privacy ------------------------------------------------
      heading(zh ? '数据检查与隐私' : 'Data checks and privacy'),
      for (final e in ds.cleaningLog.where((e) => !e.action.startsWith('downcast_')))
        pw.Bullet(text: '${e.column}: ${s.action(e.action)}', style: st(8), bulletSize: 2.5, bulletMargin: const pw.EdgeInsets.only(top: 3.5, right: 6)),
      pw.SizedBox(height: 4),
      pw.Text(
        zh
            ? '原始数值未被修改。${ds.privacy.namesProtected > 0 ? '${ds.privacy.namesProtected} 个名称' : ''}'
                '${ds.privacy.found.isNotEmpty ? '及 ${ds.privacy.found.values.fold<int>(0, (a, b) => a + b)} 处联系方式或证件信息' : ''}在发送给 AI 之前已被隐藏。'
            : 'No values were changed. '
                '${ds.privacy.namesProtected > 0 || ds.privacy.found.isNotEmpty ? '${ds.privacy.namesProtected} names and ${ds.privacy.found.values.fold<int>(0, (a, b) => a + b)} contact or ID details were hidden before any text was sent to the AI.' : 'No personal details were found.'}',
        style: st(8, color: _muted),
      ),
    ],
  ));

  return doc.save();
}

pw.Widget _monthlyTable(CashFlow cf, S s, pw.TextStyle Function(double, {PdfColor color, bool b, bool serifFace}) st) {
  final maxV = cf.monthly.map((m) => math.max(m.inflow, m.outflow)).fold<double>(1, math.max);
  pw.Widget bar(double v, PdfColor c) => pw.Container(
        alignment: pw.Alignment.centerLeft,
        child: pw.Container(width: 70 * v / maxV, height: 4, color: c),
      );
  return pw.Table(
    columnWidths: {
      0: const pw.FixedColumnWidth(54),
      1: const pw.FlexColumnWidth(1.1),
      2: const pw.FixedColumnWidth(76),
      3: const pw.FlexColumnWidth(1.1),
      4: const pw.FixedColumnWidth(76),
      5: const pw.FlexColumnWidth(1),
    },
    border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _rule, width: 0.4)),
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEFECE5)),
        children: [
          for (final h in [s.zh ? '月份' : 'Month', s.moneyIn, '', s.moneyOut, '', s.net])
            pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5), child: pw.Text(h, style: st(7.5, color: _muted, b: true))),
        ],
      ),
      for (final m in cf.monthly)
        pw.TableRow(verticalAlignment: pw.TableCellVerticalAlignment.middle, children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: pw.Text('${fmtMonth(m.month, s.zh)} ${m.month.year}', style: st(8)),
          ),
          pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(fmtMoney(m.inflow), style: st(8), textAlign: pw.TextAlign.right)),
          bar(m.inflow, _accent),
          pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(fmtMoney(m.outflow), style: st(8), textAlign: pw.TextAlign.right)),
          bar(m.outflow, _out),
          pw.Padding(
            padding: const pw.EdgeInsets.all(3),
            child: pw.Text(fmtMoney(m.net), style: st(8, color: m.net < 0 ? _brick : _accent, b: true), textAlign: pw.TextAlign.right),
          ),
        ]),
    ],
  );
}

pw.Widget _shares(List<CategoryShare> items, pw.TextStyle Function(double, {PdfColor color, bool b, bool serifFace}) st, PdfColor c) {
  final maxShare = items.map((i) => i.share).fold<double>(0.0001, math.max);
  return pw.Column(children: [
    for (final it in items.take(6))
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(children: [
          pw.SizedBox(width: 110, child: pw.Text(it.category, style: st(8.5))),
          pw.Expanded(
            child: pw.Container(alignment: pw.Alignment.centerLeft, child: pw.Container(width: 200 * it.share / maxShare, height: 5, color: c)),
          ),
          pw.SizedBox(width: 70, child: pw.Text(fmtMoney(it.amount), style: st(8.5), textAlign: pw.TextAlign.right)),
          pw.SizedBox(width: 36, child: pw.Text('${(it.share * 100).round()}%', style: st(8, color: _muted), textAlign: pw.TextAlign.right)),
        ]),
      ),
  ]);
}
