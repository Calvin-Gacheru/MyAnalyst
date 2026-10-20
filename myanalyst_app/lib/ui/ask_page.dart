import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/strings.dart';
import '../models/models.dart';
import '../state/app_controller.dart';
import '../theme/tokens.dart';
import 'charts.dart';
import 'common.dart';

class AskPage extends StatefulWidget {
  const AskPage({super.key});

  @override
  State<AskPage> createState() => _AskPageState();
}

class _AskPageState extends State<AskPage> {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _focus = FocusNode();
  int _seen = 0;

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send([String? preset]) {
    final app = AppScope.read(context);
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || app.asking) return;
    _input.clear();
    unawaited(app.ask(text));
  }

  void _scrollToEndSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ds = app.dataset!;
    final compact = isCompact(context);

    // Follow the conversation when a question is added or answered.
    final signature = app.exchanges.length * 2 + (app.asking ? 0 : 1);
    if (signature != _seen) {
      _seen = signature;
      _scrollToEndSoon();
    }

    return Column(
      children: [
        Expanded(
          child: PageFrame(
            controller: _scroll,
            maxWidth: 780,
            children: [
              PageHeader(
                eyebrow: app.strings.askEyebrow,
                title: app.strings.askTitle(
                    app.strings.zh ? humanizeFileName(ds.fileName) : humanizeFileName(ds.fileName).toLowerCase()),
                subtitle: app.strings.askLead,
              ),
              if (app.exchanges.isEmpty)
                _Suggestions(questions: _suggestionsFor(ds, app.strings), onPick: _send)
              else
                for (final ex in app.exchanges) _ExchangeView(ex),
            ],
          ),
        ),
        _Composer(
          controller: _input,
          focus: _focus,
          busy: app.asking,
          fileName: ds.fileName,
          compact: compact,
          onSend: _send,
        ),
      ],
    );
  }

  static List<String> _suggestionsFor(Dataset ds, S s) {
    final cols = ds.dictionary.map((e) => e.column.toLowerCase()).toSet();
    if (ds.cashFlow.detected && !ds.cashFlow.inflowOnly) {
      return s.zh
          ? const ['为什么我的现金在减少？', '哪里可以节省成本？', '哪个月份经营得最好？', '批发客户的回款准时吗？']
          : const [
              'Why is my cash going down?',
              'Where can I cut costs?',
              'Which month was the best, and why?',
              'Are my wholesale customers paying on time?',
            ];
    }
    if (cols.contains('coffee_name')) {
      return s.zh
          ? const ['哪些饮品最赚钱？', '刷卡和现金顾客有什么不同？', '一周中哪天最忙？', '能预测下个月的营业额吗？']
          : const [
              'Which drinks bring in the most money?',
              'How do card and cash customers compare?',
              'Which day of the week is busiest?',
              'Can you forecast next month\'s revenue?',
            ];
    }
    if (s.zh) return const ['哪个类别的收入最高？', '这份数据中最重要的三件事是什么？', '有哪些值得注意的异常？'];
    final category = ds.dictionary.where((e) => e.dataType.contains('cat')).map((e) => humanize(e.column)).toList();
    final numeric = ds.dictionary
        .where((e) => e.dataType.contains('float') || e.dataType.contains('int'))
        .map((e) => humanize(e.column))
        .where((c) => !c.toLowerCase().contains('id'))
        .toList();
    return [
      if (category.isNotEmpty && numeric.isNotEmpty)
        'Which ${category.first.toLowerCase()} has the highest average ${numeric.first.toLowerCase()}?',
      if (numeric.length >= 2) 'Is there a relationship between ${numeric[0].toLowerCase()} and ${numeric[1].toLowerCase()}?',
      if (category.length >= 2) 'How does ${category[1].toLowerCase()} vary across ${category[0].toLowerCase()}?',
      'What are the three most important things in this data?',
    ];
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.questions, required this.onPick});
  final List<String> questions;
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(S.of(context).tryThese, style: Txt.eyebrow),
        const SizedBox(height: Space.sm),
        const Divider(),
        for (final q in questions) ...[
          _SuggestionRow(q, onTap: () => onPick(q)),
          const Divider(),
        ],
      ],
    );
  }
}

class _SuggestionRow extends StatefulWidget {
  const _SuggestionRow(this.text, {required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  State<_SuggestionRow> createState() => _SuggestionRowState();
}

class _SuggestionRowState extends State<_SuggestionRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: Space.xxs),
            child: Row(children: [
              Expanded(
                child: Text(widget.text,
                    style: Txt.prose.copyWith(fontSize: 16, color: _hover ? Palette.accent : Palette.ink)),
              ),
              Icon(Icons.north_east, size: 16, color: _hover ? Palette.accent : Palette.inkFaint),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ExchangeView extends StatelessWidget {
  const _ExchangeView(this.ex);
  final Exchange ex;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(S.of(context).youAsked(fmtTime(ex.askedAt)), style: Txt.caption),
          const SizedBox(height: 4),
          SelectableText(ex.question, style: Txt.heading.copyWith(fontFamily: 'Plex Sans', fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: Space.md),
          if (ex.pending)
            const _Working()
          else if (ex.errorMessage != null)
            _ErrorBlock(ex)
          else
            _AnswerBlock(ex.answer!),
        ],
      ),
    );
  }
}

/// Left-ruled block, the visual signature of an answer.
class _Ruled extends StatelessWidget {
  const _Ruled({required this.child, this.color = Palette.accent});
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: Space.md + 2),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 2))),
      child: child,
    );
  }
}

class _Working extends StatefulWidget {
  const _Working();

  @override
  State<_Working> createState() => _WorkingState();
}

class _WorkingState extends State<_Working> {
  int _i = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (_i < 3) setState(() => _i++);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Ruled(
      color: Palette.ruleStrong,
      child: Semantics(
        liveRegion: true,
        child: Row(children: [
          const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Palette.accent)),
          const SizedBox(width: Space.sm),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text('${S.of(context).workingPhases[_i]}…', key: ValueKey(_i), style: Txt.bodyMuted),
          ),
        ]),
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock(this.ex);
  final Exchange ex;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return _Ruled(
      color: Palette.brick,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ex.errorMessage!, style: Txt.body.copyWith(color: Palette.brick)),
        const SizedBox(height: Space.xs),
        TextButton.icon(
          onPressed: app.asking ? null : () => app.retry(ex),
          icon: const Icon(Icons.refresh, size: 16),
          label: Text(S.of(context).tryAgain),
        ),
      ]),
    );
  }
}

class _AnswerBlock extends StatefulWidget {
  const _AnswerBlock(this.a);
  final Answer a;

  @override
  State<_AnswerBlock> createState() => _AnswerBlockState();
}

class _AnswerBlockState extends State<_AnswerBlock> {
  bool _showCode = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.a;
    final failed = a.failed;

    return _Ruled(
      color: failed ? Palette.amber : Palette.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (failed) ...[
            Text(S.of(context).couldntAnswer, style: Txt.label.copyWith(color: Palette.amber)),
            const SizedBox(height: 4),
            Text(
              S.of(context).triedTimes(a.attempts),
              style: Txt.body,
            ),
          ] else
            // Plain text only: the answer is model output and is never
            // interpreted as markup or links.
            SelectableText(a.text, style: Txt.prose),
          if (a.resultPreview != null) ...[
            const SizedBox(height: Space.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
              decoration: const BoxDecoration(color: Palette.sunken, borderRadius: BorderRadius.all(Radii.sm)),
              child: SelectableText('${S.of(context).result}: ${a.resultPreview}', style: Txt.monoSmall),
            ),
          ],
          if (a.chart != null) ...[
            const SizedBox(height: Space.lg),
            ChartCard(chart: a.chart!, height: 220),
          ],
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.md,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!failed && a.corrections > 0)
                Tooltip(
                  message: S.of(context).fixedTooltip,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.build_outlined, size: 14, color: Palette.inkFaint),
                    const SizedBox(width: 5),
                    Text(
                      S.of(context).fixedTimes(a.corrections),
                      style: Txt.caption,
                    ),
                  ]),
                ),
              if (a.generatedCode.isNotEmpty)
                TextButton(
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6)),
                  onPressed: () => setState(() => _showCode = !_showCode),
                  child: Text(_showCode ? S.of(context).hideCode : S.of(context).showCode),
                ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topLeft,
            child: _showCode ? _CodeBlock(a.generatedCode) : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock(this.code);
  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: Space.xs),
      decoration: BoxDecoration(
        color: Palette.sunken,
        border: Border.all(color: Palette.rule),
        borderRadius: const BorderRadius.all(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.md, Space.xs, Space.xs, 0),
            child: Row(children: [
              Text(S.of(context).codeCaption, style: Txt.caption),
              const Spacer(),
              IconButton(
                tooltip: S.of(context).copyCode,
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  showMessage(context, S.of(context).codeCopied);
                },
                icon: const Icon(Icons.copy_outlined, color: Palette.inkMuted),
              ),
            ]),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.md),
            child: SelectableText(code, style: Txt.mono),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focus,
    required this.busy,
    required this.fileName,
    required this.compact,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool busy;
  final String fileName;
  final bool compact;
  final void Function([String?]) onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Palette.paper,
        border: Border(top: BorderSide(color: Palette.rule)),
      ),
      padding: EdgeInsets.fromLTRB(compact ? Space.md : Space.xxl, Space.md, compact ? Space.md : Space.xxl, Space.md),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: CallbackShortcuts(
                      // Enter sends; Shift+Enter adds a new line.
                      bindings: {const SingleActivator(LogicalKeyboardKey.enter): () => onSend()},
                      child: ValueListenableBuilder(
                        valueListenable: controller,
                        builder: (context, value, _) => TextField(
                          controller: controller,
                          focusNode: focus,
                          enabled: !busy,
                          minLines: 1,
                          maxLines: 5,
                          maxLength: AppController.maxQuestionLength,
                          maxLengthEnforcement: MaxLengthEnforcement.enforced,
                          textInputAction: TextInputAction.newline,
                          style: Txt.body.copyWith(fontSize: 15),
                          decoration: InputDecoration(
                            hintText: busy ? S.of(context).workingOnLast : S.of(context).askHint(fileName),
                            // Show the counter only when it's useful.
                            counterText: value.text.length > AppController.maxQuestionLength - 150
                                ? '${value.text.length}/${AppController.maxQuestionLength}'
                                : '',
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: ValueListenableBuilder(
                      valueListenable: controller,
                      builder: (context, value, _) => FilledButton(
                        onPressed: busy || value.text.trim().isEmpty ? null : () => onSend(),
                        child: Text(S.of(context).askButton),
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                compact
                    ? S.of(context).answersDisclaimerShort
                    : S.of(context).answersDisclaimer,
                style: Txt.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
