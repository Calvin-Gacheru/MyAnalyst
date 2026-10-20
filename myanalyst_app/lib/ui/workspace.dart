import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../i18n/strings.dart';
import '../models/chart_data.dart';
import '../models/models.dart';
import '../report/pdf_report.dart';
import '../state/app_controller.dart';
import '../theme/tokens.dart';
import 'ask_page.dart';
import 'cash_page.dart';
import 'charts.dart';
import 'common.dart';
import 'rules_page.dart';

class WorkspaceShell extends StatelessWidget {
  const WorkspaceShell({super.key});

  static List<(Section, String, IconData, IconData)> _items(S s) => [
        (Section.overview, s.navOverview, Icons.article_outlined, Icons.article),
        (Section.cash, s.navCash, Icons.account_balance_wallet_outlined, Icons.account_balance_wallet),
        (Section.data, s.navData, Icons.table_chart_outlined, Icons.table_chart),
        (Section.ask, s.navAsk, Icons.chat_bubble_outline, Icons.chat_bubble),
        (Section.rules, s.navRules, Icons.rule_outlined, Icons.rule),
      ];

  Widget _page(Section s) => switch (s) {
        Section.overview => const OverviewPage(),
        Section.cash => const CashFlowPage(),
        Section.data => const DataPage(),
        Section.ask => const AskPage(),
        Section.rules => const RulesPage(),
      };

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    final ds = app.dataset!;
    final items = _items(s);

    if (isCompact(context)) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Palette.paper,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          titleSpacing: 0,
          leading: IconButton(
            tooltip: s.backToStart,
            onPressed: () => _confirmLeave(context),
            icon: const Icon(Icons.arrow_back, color: Palette.ink),
          ),
          title: Text(humanizeFileName(ds.fileName), style: Txt.heading, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: s.exportPdf,
              onPressed: () => exportReport(context),
              icon: const Icon(Icons.picture_as_pdf_outlined, color: Palette.ink),
            ),
            const LanguageToggle(dense: true),
            const SizedBox(width: 4),
          ],
          bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider()),
        ),
        body: _page(app.section),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Palette.rule))),
          child: NavigationBar(
            selectedIndex: app.section.index,
            onDestinationSelected: (i) => app.go(Section.values[i]),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              for (final (_, label, icon, selected) in items)
                NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: label),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          _Sidebar(items: items),
          const VerticalDivider(width: 1, color: Palette.rule),
          Expanded(child: _page(app.section)),
        ],
      ),
    );
  }
}

/// Builds the PDF on the device and opens the system share sheet.
Future<void> exportReport(BuildContext context) async {
  final app = AppScope.read(context);
  final s = app.strings;
  final ds = app.dataset;
  if (ds == null) return;
  showMessage(context, s.preparingReport);
  try {
    final bytes = await buildReport(ds, s, preparedFor: app.isDemo ? null : app.username);
    final name = '${ds.fileName.replaceAll(RegExp(r'\.csv$', caseSensitive: false), '')}_report.pdf';
    await Printing.sharePdf(bytes: bytes, filename: name);
    if (context.mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
  } catch (_) {
    if (context.mounted) showMessage(context, s.reportFailed);
  }
}

Future<void> _confirmLeave(BuildContext context) async {
  final app = AppScope.read(context);
  final s = app.strings;
  // Nothing to lose before any question is asked: leave straight away.
  if (app.exchanges.isEmpty) {
    app.startOver();
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Palette.sheet,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radii.lg)),
      title: Text(s.leaveTitle, style: Txt.heading),
      content: Text(s.leaveBody, style: Txt.bodyMuted),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.leave)),
      ],
    ),
  );
  if (ok == true) app.startOver();
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.items});
  final List<(Section, String, IconData, IconData)> items;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    final ds = app.dataset!;

    return Container(
      width: 248,
      color: Palette.paper,
      padding: const EdgeInsets.fromLTRB(Space.md, Space.lg, Space.md, Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xs),
            child: Row(children: [
              CustomPaint(size: const Size(18, 18), painter: MarkPainter()),
              const SizedBox(width: 9),
              Text('MyAnalyst', style: Txt.heading.copyWith(fontSize: 18)),
            ]),
          ),
          const SizedBox(height: Space.xl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xs),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.dataset, style: Txt.eyebrow),
              const SizedBox(height: 6),
              Text(ds.fileName, style: Txt.monoSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(s.rowsCols(fmtInt(ds.rowCount), ds.columnCount), style: Txt.caption),
              Text(s.opened(fmtTime(ds.uploadedAt)), style: Txt.caption),
            ]),
          ),
          const SizedBox(height: Space.lg),
          const Divider(),
          const SizedBox(height: Space.sm),
          for (final (section, label, icon, selectedIcon) in items)
            _NavItem(
              label: label,
              icon: app.section == section ? selectedIcon : icon,
              selected: app.section == section,
              badge: section == Section.rules && app.rules.isNotEmpty
                  ? '${app.rules.length}'
                  : (section == Section.cash && ds.cashFlow.gap != null ? '!' : null),
              badgeColor: section == Section.cash ? Palette.brick : null,
              onTap: () => app.go(section),
            ),
          const SizedBox(height: Space.sm),
          const Divider(),
          const SizedBox(height: Space.xs),
          _NavItem(
            label: s.exportPdf,
            icon: Icons.picture_as_pdf_outlined,
            selected: false,
            onTap: () => exportReport(context),
          ),
          const Spacer(),
          const Align(alignment: Alignment.centerLeft, child: LanguageToggle(dense: true)),
          if (app.isDemo)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm, left: Space.xs, top: Space.xxs),
              child: Row(children: [
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: Palette.amber, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Expanded(child: Text(s.demoNotConnected, style: Txt.caption)),
              ]),
            ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _confirmLeave(context),
              icon: const Icon(Icons.add, size: 18),
              label: Text(s.newAnalysis),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badge,
    this.badgeColor,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;
  final Color? badgeColor;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    return Semantics(
      button: true,
      selected: sel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            margin: const EdgeInsets.symmetric(vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 9),
            decoration: BoxDecoration(
              color: sel ? Palette.sheet : (_hover ? Palette.sunken.withOpacity(0.7) : Colors.transparent),
              border: Border.all(color: sel ? Palette.rule : Colors.transparent),
              borderRadius: const BorderRadius.all(Radii.md),
            ),
            child: Row(children: [
              Icon(widget.icon, size: 18, color: sel ? Palette.accent : Palette.inkMuted),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(widget.label,
                    style: Txt.label.copyWith(
                        color: sel ? Palette.ink : Palette.inkMuted, fontWeight: sel ? FontWeight.w600 : FontWeight.w500)),
              ),
              if (widget.badge != null)
                widget.badgeColor != null
                    ? Container(
                        width: 18,
                        height: 18,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: widget.badgeColor, shape: BoxShape.circle),
                        child: Text(widget.badge!, style: Txt.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                      )
                    : Text(widget.badge!, style: Txt.caption.copyWith(fontFeatures: Txt.tabular)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Overview
// ===========================================================================

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    final ds = app.dataset!;
    final cf = ds.cashFlow;
    final paragraphs =
        ds.executiveSummary.split(RegExp(r'\n\s*\n')).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    final checks = ds.cleaningLog.where((e) => !_isHousekeeping(e.action)).length;
    final pii = ds.privacy.found.entries.map((e) => s.piiKind(e.key, e.value)).join(s.zh ? '、' : ', ');

    return PageFrame(
      children: [
        PageHeader(
          eyebrow: s.navOverview,
          title: humanizeFileName(ds.fileName),
          subtitle: s.analysedOn(fmtDay(ds.uploadedAt, s.zh), fmtTime(ds.uploadedAt)),
        ),
        if (cf.gap != null) ...[
          Notice(
            title: s.gapAlertTitle(cf.gap!.likely),
            body: s.gapAlertBody(fmtDate(cf.gap!.date, s.zh), cf.gap!.weeksAway, fmtMoney(cf.gap!.suggestedAmount)),
            tone: cf.gap!.likely ? Palette.brick : Palette.amber,
            wash: cf.gap!.likely ? Palette.brickWash : Palette.amberWash,
            action: TextButton(
              style: TextButton.styleFrom(
                foregroundColor: cf.gap!.likely ? Palette.brick : Palette.amber,
                padding: const EdgeInsets.symmetric(vertical: 6),
              ),
              onPressed: () => app.go(Section.cash),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(s.seeCashFlow),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward, size: 15),
              ]),
            ),
          ),
          const SizedBox(height: Space.lg),
        ],
        StatStrip(stats: [
          if (cf.detected && !cf.inflowOnly) ...[
            (s.cashNow, cf.cashOnHand == null ? '—' : fmtMoneyShort(cf.cashOnHand!, s.zh)),
            (s.runway, cf.runwayMonths == null ? '—' : s.runwayMonths(cf.runwayMonths!.toStringAsFixed(1))),
            ('${s.net} / ${s.zh ? '月' : 'mo'}', fmtMoneyShort(cf.avgNet, s.zh)),
            (s.rows, fmtInt(ds.rowCount)),
          ] else ...[
            (s.rows, fmtInt(ds.rowCount)),
            (s.columns, fmtInt(ds.columnCount)),
            (s.fixesApplied, fmtInt(checks)),
            (s.charts, fmtInt(ds.charts.where((c) => c is! UnsupportedChart).length)),
          ],
        ]),
        SectionHeading(s.whatDataSays),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.readingWidth),
          child: paragraphs.isEmpty
              ? Text(s.noSummary, style: Txt.bodyMuted)
              : SelectionArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < paragraphs.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.md),
                          child: Text(paragraphs[i], style: i == 0 ? Txt.proseLead : Txt.prose),
                        ),
                    ],
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: Text(s.writtenAutomatically, style: Txt.caption),
        ),
        const SizedBox(height: Space.md),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.shield_outlined, size: 15, color: Palette.accent),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(s.privacyLine(ds.privacy.namesProtected, pii),
                style: Txt.caption.copyWith(color: Palette.inkMuted)),
          ),
        ]),
        if (ds.charts.isNotEmpty) ...[
          SectionHeading(s.charts, meta: s.prepared(ds.charts.length)),
          _ChartGrid(charts: ds.charts),
        ],
        const SizedBox(height: Space.xl),
        _NextSteps(
          onAsk: () => app.go(Section.ask),
          onSecondary: () => app.go(cf.detected && !cf.inflowOnly ? Section.cash : Section.data),
          secondaryLabel: cf.detected && !cf.inflowOnly ? s.seeCashFlow : s.reviewData,
        ),
      ],
    );
  }
}

class _ChartGrid extends StatelessWidget {
  const _ChartGrid({required this.charts});
  final List<ChartData> charts;

  bool _isWide(ChartData c) => c is LineSpec;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final twoUp = box.maxWidth >= 760;
      const gap = Space.md;
      final half = (box.maxWidth - gap) / 2;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final c in charts)
            SizedBox(
              width: twoUp && !_isWide(c) ? half : box.maxWidth,
              child: ChartCard(chart: c, height: _isWide(c) ? 260 : 220),
            ),
        ],
      );
    });
  }
}

class _NextSteps extends StatelessWidget {
  const _NextSteps({required this.onAsk, required this.onSecondary, required this.secondaryLabel});
  final VoidCallback onAsk;
  final VoidCallback onSecondary;
  final String secondaryLabel;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Sheet(
      color: Palette.accentWash.withOpacity(0.5),
      child: Wrap(
        spacing: Space.lg,
        runSpacing: Space.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.haveQuestion, style: Txt.heading),
              const SizedBox(height: 4),
              Text(s.haveQuestionHint, style: Txt.bodyMuted),
            ]),
          ),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
            OutlinedButton(onPressed: onSecondary, child: Text(secondaryLabel)),
            FilledButton(onPressed: onAsk, child: Text(s.askQuestion)),
          ]),
        ],
      ),
    );
  }
}

// ===========================================================================
// Data: dictionary + checks
// ===========================================================================

bool _isHousekeeping(String action) => action.startsWith('downcast_');

class DataPage extends StatelessWidget {
  const DataPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    final ds = app.dataset!;
    final log = ds.cleaningLog.where((e) => !_isHousekeeping(e.action)).toList();
    final housekeeping = ds.cleaningLog.length - log.length;

    return PageFrame(
      children: [
        PageHeader(eyebrow: s.navData, title: s.dataTitle, subtitle: s.dataLead),
        SectionHeading(s.columnsHeading, top: 0, meta: s.nColumns(ds.dictionary.length)),
        _Dictionary(entries: ds.dictionary),
        SectionHeading(s.changesHeading, meta: log.isEmpty ? null : s.nChanges(log.length)),
        if (log.isEmpty) Text(s.noChanges, style: Txt.bodyMuted) else _ChangeLog(entries: log),
        if (housekeeping > 0)
          Padding(
            padding: const EdgeInsets.only(top: Space.md),
            child: Text(s.housekeeping(housekeeping), style: Txt.caption),
          ),
      ],
    );
  }
}

class _Dictionary extends StatelessWidget {
  const _Dictionary({required this.entries});
  final List<DataDictionaryEntry> entries;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    if (entries.isEmpty) return Text(s.noDictionary, style: Txt.bodyMuted);

    if (isCompact(context)) {
      return Column(children: [
        for (final e in entries) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(e.column, style: Txt.mono.copyWith(fontWeight: FontWeight.w500))),
                Pill(e.dataType),
              ]),
              const SizedBox(height: 4),
              Text(e.businessMeaning.isEmpty ? '—' : e.businessMeaning, style: Txt.body),
              if (e.notes.isNotEmpty) Text(e.notes, style: Txt.caption),
            ]),
          ),
          const Divider(),
        ],
      ]);
    }

    TableRow row(List<Widget> cells, {bool header = false}) => TableRow(
          decoration: BoxDecoration(
            color: header ? Palette.sunken : null,
            border: const Border(bottom: BorderSide(color: Palette.rule)),
          ),
          children: [
            for (final c in cells)
              Padding(padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 12), child: c),
          ],
        );
    final head = Txt.caption.copyWith(fontWeight: FontWeight.w600, color: Palette.inkMuted);

    return ClipRRect(
      borderRadius: const BorderRadius.all(Radii.lg),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Palette.sheet,
          border: Border.all(color: Palette.rule),
          borderRadius: const BorderRadius.all(Radii.lg),
        ),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(1.1),
            1: FlexColumnWidth(2.2),
            2: IntrinsicColumnWidth(),
            3: FlexColumnWidth(1.6),
          },
          children: [
            row(header: true, [
              Text(s.colColumn, style: head),
              Text(s.colMeaning, style: head),
              Text(s.colType, style: head),
              Text(s.colNotes, style: head),
            ]),
            for (final e in entries)
              row([
                Text(e.column, style: Txt.monoSmall.copyWith(fontWeight: FontWeight.w500)),
                Text(e.businessMeaning.isEmpty ? '—' : e.businessMeaning, style: Txt.body),
                Align(alignment: Alignment.centerLeft, child: Pill(e.dataType)),
                Text(e.notes, style: Txt.bodyMuted.copyWith(fontSize: 13.5)),
              ]),
          ],
        ),
      ),
    );
  }
}

class _ChangeLog extends StatelessWidget {
  const _ChangeLog({required this.entries});
  final List<CleaningLogEntry> entries;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    // Group by column so a reader sees everything that happened to one field together.
    final byColumn = <String, List<CleaningLogEntry>>{};
    for (final e in entries) {
      (byColumn[e.column] ??= []).add(e);
    }
    final compact = isCompact(context);

    return Column(
      children: [
        for (final MapEntry(key: column, value: items) in byColumn.entries) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            child: Flex(
              direction: compact ? Axis.vertical : Axis.horizontal,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: compact ? null : 200,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: compact ? Space.xs : 0),
                    child: Text(column, style: Txt.monoSmall.copyWith(fontWeight: FontWeight.w500)),
                  ),
                ),
                Flexible(
                  fit: compact ? FlexFit.loose : FlexFit.tight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.xs),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.action(e.action), style: Txt.label),
                            if (e.detail.isNotEmpty) Text(e.detail, style: Txt.caption),
                          ]),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
        ],
      ],
    );
  }
}
