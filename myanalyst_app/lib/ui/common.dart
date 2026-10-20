import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../state/app_controller.dart';
import '../theme/tokens.dart';

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

final _int = NumberFormat.decimalPattern('en');
final _compact = NumberFormat.compact(locale: 'en');

String fmtInt(num n) => _int.format(n);

String fmtAxis(double v) {
  if (v.abs() >= 10000) return _compact.format(v);
  if (v == v.roundToDouble()) return _int.format(v);
  return v.toStringAsFixed(v.abs() < 10 ? 1 : 0);
}

String fmtValue(double v) {
  if (v == v.roundToDouble()) return _int.format(v);
  return NumberFormat('#,##0.##', 'en').format(v);
}

String fmtTime(DateTime t) => DateFormat('HH:mm').format(t);

/// Language-aware dates without locale data: "12 Dec" / "12月12日".
String fmtDay(DateTime t, [bool zh = false]) => zh ? '${t.month}月${t.day}日' : DateFormat('d MMM').format(t);
String fmtDate(DateTime t, [bool zh = false]) =>
    zh ? '${t.year}年${t.month}月${t.day}日' : DateFormat('d MMM yyyy').format(t);
String fmtMonth(DateTime t, [bool zh = false]) => zh ? '${t.month}月' : DateFormat('MMM').format(t);

/// Whole currency units with grouping: 278,550 / −66,094.
String fmtMoney(double v) => (v < 0 ? '−' : '') + _int.format(v.abs().round());

/// Compact money for tight spaces: 279k / 1.4m (English), 27.9万 (Chinese).
String fmtMoneyShort(double v, [bool zh = false]) {
  final a = v.abs();
  final sign = v < 0 ? '−' : '';
  if (zh && a >= 10000) return '$sign${(a / 10000).toStringAsFixed(a >= 1e5 ? 0 : 1)}万';
  if (a >= 1e6) return '$sign${(a / 1e6).toStringAsFixed(1)}m';
  if (a >= 1e3) return '$sign${(a / 1e3).toStringAsFixed(a >= 1e5 ? 0 : 1)}k';
  return '$sign${a.round()}';
}

/// "coffee_sales.csv" -> "Coffee sales"
String humanizeFileName(String fileName) {
  final base = fileName.replaceAll(RegExp(r'\.csv$', caseSensitive: false), '');
  return humanize(base);
}

/// "Counts by coffee_name" -> "Counts by coffee name"; "money" -> "Money".
/// Backend chart titles use raw column names; readers shouldn't have to.
String humanize(String s) {
  final spaced = s
      .replaceAll(RegExp(r'[_]+'), ' ')
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]!.toLowerCase()}')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (spaced.isEmpty) return spaced;
  return spaced[0].toUpperCase() + spaced.substring(1);
}

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------

bool isCompact(BuildContext context) => MediaQuery.sizeOf(context).width < Breakpoints.compact;

/// Scrollable page body with consistent gutters and a max content width.
class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.children, this.maxWidth = Breakpoints.contentWidth, this.controller});

  final List<Widget> children;
  final double maxWidth;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    return Scrollbar(
      controller: controller,
      child: SingleChildScrollView(
        controller: controller,
        padding: EdgeInsets.fromLTRB(
          compact ? Space.md : Space.xxl,
          compact ? Space.lg : Space.xxl,
          compact ? Space.md : Space.xxl,
          Space.xxxl,
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ),
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.eyebrow, required this.title, this.subtitle, this.trailing});

  final String eyebrow;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(eyebrow.toUpperCase(), style: Txt.eyebrow),
                const SizedBox(height: Space.xs),
                Text(title, style: isCompact(context) ? Txt.title : Txt.title.copyWith(fontSize: 30)),
                if (subtitle != null) ...[
                  const SizedBox(height: Space.xs),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: Breakpoints.readingWidth),
                    child: Text(subtitle!, style: Txt.bodyMuted),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Section title with a hairline under it, like a report heading.
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.meta, this.top = Space.xxl});

  final String title;
  final String? meta;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(title, style: Txt.heading)),
              if (meta != null) Text(meta!, style: Txt.caption),
            ],
          ),
          const SizedBox(height: Space.sm),
          const Divider(),
        ],
      ),
    );
  }
}

/// Row of key figures separated by hairlines.
class StatStrip extends StatelessWidget {
  const StatStrip({super.key, required this.stats});

  final List<(String label, String value)> stats;

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    final cells = [
      for (final (label, value) in stats)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.md, horizontal: Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Txt.caption),
              const SizedBox(height: Space.xxs),
              Text(value, style: compact ? Txt.figure.copyWith(fontSize: 22) : Txt.figure),
            ],
          ),
        ),
    ];
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border.symmetric(horizontal: BorderSide(color: Palette.rule)),
      ),
      child: compact
          ? Wrap(children: [for (final c in cells) SizedBox(width: 160, child: c)])
          : IntrinsicHeight(
              child: Row(
                children: [
                  for (var i = 0; i < cells.length; i++) ...[
                    if (i > 0) const VerticalDivider(width: 1, color: Palette.rule),
                    Expanded(child: cells[i]),
                  ],
                ],
              ),
            ),
    );
  }
}

/// Flat bordered surface. Hairline border, no shadow.
class Sheet extends StatelessWidget {
  const Sheet({super.key, required this.child, this.padding = const EdgeInsets.all(Space.lg), this.color});

  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Palette.sheet,
        border: Border.all(color: Palette.rule),
        borderRadius: const BorderRadius.all(Radii.lg),
      ),
      child: child,
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = Palette.inkMuted, this.background = Palette.sunken});

  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: background, borderRadius: const BorderRadius.all(Radii.sm)),
      child: Text(text, style: Txt.caption.copyWith(color: color, fontWeight: FontWeight.w500)),
    );
  }
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// "中文" / "English" switch. Shows the language you'd switch *to*, in that
/// language, so someone who can't read the current one can still find it.
class LanguageToggle extends StatelessWidget {
  const LanguageToggle({super.key, this.dense = false});
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Semantics(
      button: true,
      label: app.strings.zh ? 'Switch to English' : '切换到中文',
      child: TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: Palette.inkMuted,
          padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 6 : 10),
        ),
        onPressed: app.toggleLanguage,
        icon: const Icon(Icons.translate, size: 16),
        label: Text(app.strings.switchLanguage, style: Txt.label.copyWith(color: Palette.inkMuted)),
      ),
    );
  }
}

/// Left-ruled notice block for warnings and confirmations.
class Notice extends StatelessWidget {
  const Notice({
    super.key,
    required this.title,
    required this.body,
    this.tone = Palette.brick,
    this.wash = Palette.brickWash,
    this.icon = Icons.warning_amber_rounded,
    this.action,
  });

  final String title;
  final String body;
  final Color tone;
  final Color wash;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.md),
      decoration: BoxDecoration(
        color: wash,
        border: Border(left: BorderSide(color: tone, width: 3)),
        borderRadius: const BorderRadius.horizontal(right: Radii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 18, color: tone)),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Txt.label.copyWith(color: tone, fontWeight: FontWeight.w600, fontSize: 14.5)),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(body, style: Txt.body.copyWith(color: Palette.ink)),
              ],
              if (action != null) ...[const SizedBox(height: Space.xs), action!],
            ]),
          ),
        ],
      ),
    );
  }
}

/// Small ledger mark: three rising bars on a baseline. Drawn, not an icon font.
class MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Palette.accent;
    final w = size.width / 5;
    canvas.drawRect(Rect.fromLTWH(0, size.height * .55, w, size.height * .45), p);
    canvas.drawRect(Rect.fromLTWH(w * 2, size.height * .3, w, size.height * .7), p);
    canvas.drawRect(Rect.fromLTWH(w * 4, size.height * .05, w, size.height * .95), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      CustomPaint(size: Size.square(size + 2), painter: MarkPainter()),
      const SizedBox(width: 10),
      Text('MyAnalyst', style: Txt.heading.copyWith(fontSize: size, fontWeight: FontWeight.w500)),
      if (app.isDemo) ...[
        const SizedBox(width: Space.sm),
        Pill(app.strings.demoData, color: Palette.amber, background: Palette.amberWash),
      ],
    ]);
  }
}
