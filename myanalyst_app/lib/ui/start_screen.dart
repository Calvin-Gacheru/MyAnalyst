import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../data/repository.dart';
import '../i18n/strings.dart';
import '../models/models.dart';
import '../state/app_controller.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'lock_screen.dart';

class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    final compact = isCompact(context);
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TopBar(),
        SizedBox(height: compact ? Space.xxl : Space.xxxl),
        Text(s.startTitle, style: compact ? Txt.title.copyWith(fontSize: 30) : Txt.display),
        const SizedBox(height: Space.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(s.startLead, style: Txt.proseLead.copyWith(fontSize: compact ? 17 : 19)),
        ),
        const SizedBox(height: Space.xl),
        const BiometricOffer(),
        if (app.processingFile != null) const _Processing() else const _UploadPanel(),
        if (app.processingFile == null) ...[
          if (app.library.isNotEmpty || app.libraryLoading) ...[
            const SizedBox(height: Space.xxl),
            const _Library(),
          ],
          const SizedBox(height: Space.xxl),
          const _Samples(),
        ],
      ],
    );

    return Scaffold(
      body: SafeArea(
        child: PageFrame(
          maxWidth: 1080,
          children: [
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: main),
                  const SizedBox(width: Space.xxxl),
                  const Expanded(flex: 4, child: Padding(padding: EdgeInsets.only(top: 132), child: _HowItWorks())),
                ],
              )
            else ...[
              main,
              const SizedBox(height: Space.xxl),
              const _HowItWorks(),
            ],
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    return Row(children: [
      const Expanded(child: Align(alignment: Alignment.centerLeft, child: Wordmark())),
      const LanguageToggle(dense: true),
      if (app.signedIn)
        PopupMenuButton<String>(
          tooltip: app.username,
          position: PopupMenuPosition.under,
          color: Palette.sheet,
          surfaceTintColor: Colors.transparent,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radii.md), side: BorderSide(color: Palette.rule)),
          onSelected: (v) async {
            if (v == 'out') app.signOut();
            if (v == 'bio') {
              final err = await app.setBiometric(!app.biometricEnabled);
              if (err != null && context.mounted) showMessage(context, err);
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(enabled: false, child: Text(app.username ?? '', style: Txt.caption)),
            if (app.biometricAvailable)
              PopupMenuItem(
                value: 'bio',
                child: Row(children: [
                  const Icon(Icons.fingerprint, size: 18, color: Palette.inkMuted),
                  const SizedBox(width: Space.xs),
                  Expanded(child: Text(s.fingerprintUnlock, style: Txt.body)),
                  Text(app.biometricEnabled ? s.on : s.off,
                      style: Txt.caption.copyWith(color: app.biometricEnabled ? Palette.accent : Palette.inkFaint)),
                ]),
              ),
            PopupMenuItem(value: 'out', child: Text(s.signOut, style: Txt.body)),
          ],
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: CircleAvatar(
              radius: 15,
              backgroundColor: Palette.accentWash,
              child: Text((app.username ?? '?').substring(0, 1).toUpperCase(),
                  style: Txt.label.copyWith(color: Palette.accent)),
            ),
          ),
        ),
    ]);
  }
}

// ---------------------------------------------------------------------------

class _UploadPanel extends StatefulWidget {
  const _UploadPanel();

  @override
  State<_UploadPanel> createState() => _UploadPanelState();
}

class _UploadPanelState extends State<_UploadPanel> {
  FileProblem? _problem;
  bool _unreadable = false;
  bool _picking = false;

  Future<void> _pick() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _problem = null;
      _unreadable = false;
    });
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true, // read into memory; we never need a filesystem path
      );
      final file = res?.files.single;
      if (file == null || !mounted) return;
      final app = AppScope.read(context);
      final problem = app.validateFile(file.name, file.size, file.bytes);
      if (problem != null) {
        setState(() => _problem = problem);
        return;
      }
      if (file.bytes == null) {
        setState(() => _unreadable = true);
        return;
      }
      unawaited(app.uploadFile(file.name, file.bytes!));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  String _message(S s, FileProblem p) {
    final mb = (AppConfig.maxUploadBytes / (1024 * 1024)).round();
    return switch (p) {
      FileProblem.notCsv => s.errNotCsv,
      FileProblem.empty => s.errEmpty,
      FileProblem.tooBig => s.errTooBig(mb),
      FileProblem.binary => s.errBinary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final mb = (AppConfig.maxUploadBytes / (1024 * 1024)).round();
    final error = _unreadable ? s.errUnreadable : (_problem == null ? null : _message(s, _problem!));
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: Sheet(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: Space.md,
              runSpacing: Space.md,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _picking ? null : _pick,
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: Text(s.chooseCsv),
                ),
                Text(s.csvHint(mb), style: Txt.caption),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: Space.md),
              Notice(title: error, body: '', icon: Icons.error_outline),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// The backend gives no progress events, so steps advance on a schedule
/// that roughly matches real timings. The last step holds until the
/// response arrives; nothing claims "done" before it actually is.
class _Processing extends StatefulWidget {
  const _Processing();

  @override
  State<_Processing> createState() => _ProcessingState();
}

class _ProcessingState extends State<_Processing> {
  static const _schedule = [700, 1300, 1000, 900, 1200];

  int _current = 0;
  Timer? _timer;
  final _clock = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    _advance();
  }

  void _advance() {
    if (_current >= _schedule.length) return;
    _timer = Timer(Duration(milliseconds: _schedule[_current]), () {
      if (!mounted) return;
      setState(() => _current++);
      _advance();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    final steps = s.processingSteps;
    final failed = app.processingError != null;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: Sheet(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.description_outlined, size: 18, color: Palette.inkMuted),
              const SizedBox(width: Space.xs),
              Expanded(child: Text(app.processingFile ?? '', style: Txt.label, overflow: TextOverflow.ellipsis)),
              if (!failed) _Elapsed(_clock),
            ]),
            const SizedBox(height: Space.md),
            const Divider(),
            const SizedBox(height: Space.sm),
            for (var i = 0; i < steps.length; i++)
              _StepRow(
                title: steps[i].$1,
                // Real upload progress when we have it (dio onSendProgress).
                detail: i == 0 && app.uploadProgress != null && app.uploadProgress! < 1
                    ? '${steps[i].$2} · ${(app.uploadProgress! * 100).round()}%'
                    : steps[i].$2,
                state: failed
                    ? (i < _current ? _StepState.done : (i == _current ? _StepState.failed : _StepState.pending))
                    : (i < _current ? _StepState.done : (i == _current ? _StepState.active : _StepState.pending)),
              ),
            if (failed) ...[
              const SizedBox(height: Space.md),
              Notice(title: app.processingError!, body: '', icon: Icons.error_outline),
              const SizedBox(height: Space.md),
              Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
                FilledButton(onPressed: app.retryUpload, child: Text(s.tryAgain)),
                OutlinedButton(onPressed: app.cancelFailedUpload, child: Text(s.chooseAnother)),
              ]),
            ] else ...[
              const SizedBox(height: Space.sm),
              Text(s.usuallyUnderMinute, style: Txt.caption),
            ],
          ],
        ),
      ),
    );
  }
}

class _Elapsed extends StatefulWidget {
  const _Elapsed(this.clock);
  final Stopwatch clock;

  @override
  State<_Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<_Elapsed> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.clock.elapsed.inSeconds;
    return Text('${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}', style: Txt.caption.copyWith(fontFeatures: Txt.tabular));
  }
}

enum _StepState { done, active, pending, failed }

class _StepRow extends StatelessWidget {
  const _StepRow({required this.title, required this.detail, required this.state});
  final String title;
  final String detail;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final Widget marker = switch (state) {
      _StepState.done => const Icon(Icons.check, size: 16, color: Palette.accent),
      _StepState.active =>
        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.6, color: Palette.accent)),
      _StepState.failed => const Icon(Icons.close, size: 16, color: Palette.brick),
      _StepState.pending => Container(
          width: 7, height: 7, decoration: const BoxDecoration(color: Palette.ruleStrong, shape: BoxShape.circle)),
    };
    final muted = state == _StepState.pending;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 20, height: 20, child: Center(child: marker)),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Txt.label.copyWith(color: muted ? Palette.inkFaint : Palette.ink)),
              if (state == _StepState.active) Text(detail, style: Txt.caption),
            ]),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Library extends StatelessWidget {
  const _Library();

  Future<void> _delete(BuildContext context, DatasetSummary d) async {
    final app = AppScope.read(context);
    final s = app.strings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Palette.sheet,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radii.lg)),
        title: Text(s.deleteTitle, style: Txt.heading),
        content: Text(s.deleteBody, style: Txt.bodyMuted),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Palette.brick),
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final err = await app.deleteFromLibrary(d.id);
    if (err != null && context.mounted) showMessage(context, err);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.yourAnalyses, style: Txt.eyebrow),
          const SizedBox(height: Space.sm),
          const Divider(),
          if (app.libraryLoading && app.library.isEmpty)
            const Padding(
              padding: EdgeInsets.all(Space.md),
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.6)),
            ),
          for (final d in app.library.take(8)) ...[
            _Row(
              title: d.fileName,
              subtitle: '${fmtDate(d.createdAt, s.zh)} · '
                  '${d.rowCount > 0 ? s.rowsCount(d.rowCount, fmtInt(d.rowCount)) : s.filesCount(d.fileCount ?? 1)}',
              badges: [
                if (d.cashGapDate != null)
                  Pill(s.gapShort(fmtDay(d.cashGapDate!, s.zh)), color: Palette.brick, background: Palette.brickWash)
                else if (d.runwayMonths != null)
                  Pill(s.runwayShort(d.runwayMonths!.toStringAsFixed(1)), color: Palette.accent, background: Palette.accentWash),
              ],
              busy: app.openingId == d.id,
              onOpen: () async {
                final err = await app.openFromLibrary(d.id);
                if (err != null && context.mounted) showMessage(context, err);
              },
              onDelete: () => _delete(context, d),
            ),
            const Divider(),
          ],
        ],
      ),
    );
  }
}

class _Samples extends StatelessWidget {
  const _Samples();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.noFile, style: Txt.eyebrow),
          const SizedBox(height: Space.xs),
          Text(s.openSample, style: Txt.bodyMuted),
          const SizedBox(height: Space.md),
          const Divider(),
          for (final sample in sampleDatasets) ...[
            _Row(
              title: sample.fileName,
              subtitle: s.zh ? sample.descriptionZh : sample.description,
              trailing: s.rowsCount(sample.rows, fmtInt(sample.rows)),
              badges: [
                if (sample.featured)
                  Pill(s.zh ? '现金流示例' : 'Cash-flow demo', color: Palette.accent, background: Palette.accentWash),
              ],
              onOpen: () => app.openSample(sample),
            ),
            const Divider(),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    required this.title,
    required this.subtitle,
    required this.onOpen,
    this.trailing,
    this.badges = const [],
    this.busy = false,
    this.onDelete,
  });
  final String title;
  final String subtitle;
  final String? trailing;
  final List<Widget> badges;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.busy ? null : widget.onOpen,
        child: Semantics(
          button: true,
          label: widget.title,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            color: _hover ? Palette.sunken.withOpacity(0.6) : Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: Space.md, horizontal: Space.xs),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(spacing: Space.xs, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text(widget.title, style: Txt.monoSmall.copyWith(fontSize: 13.5)),
                        ...widget.badges,
                      ]),
                      const SizedBox(height: 3),
                      Text(widget.subtitle, style: Txt.bodyMuted),
                    ],
                  ),
                ),
                const SizedBox(width: Space.md),
                if (widget.trailing != null)
                  Text(widget.trailing!, style: Txt.caption.copyWith(fontFeatures: Txt.tabular)),
                if (widget.onDelete != null)
                  IconButton(
                    tooltip: S.of(context).delete,
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.delete_outline, size: 18, color: Palette.inkFaint),
                  ),
                const SizedBox(width: Space.xs),
                widget.busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.6))
                    : AnimatedSlide(
                        duration: const Duration(milliseconds: 120),
                        offset: Offset(_hover ? 0.15 : 0, 0),
                        child: Icon(Icons.arrow_forward, size: 18, color: _hover ? Palette.accent : Palette.inkFaint),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final items = s.howItWorks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.whatNext, style: Txt.eyebrow),
        const SizedBox(height: Space.md),
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 28, child: Text('${i + 1}', style: Txt.heading.copyWith(color: Palette.accent, fontSize: 17))),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(items[i].$1, style: Txt.label),
                    const SizedBox(height: 2),
                    Text(items[i].$2, style: Txt.bodyMuted.copyWith(fontSize: 14)),
                  ]),
                ),
              ],
            ),
          ),
        const Divider(),
        const SizedBox(height: Space.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.lock_outline, size: 16, color: Palette.inkMuted)),
            const SizedBox(width: Space.xs),
            Expanded(child: Text(s.privacyPromise, style: Txt.caption.copyWith(color: Palette.inkMuted))),
          ],
        ),
      ],
    );
  }
}
