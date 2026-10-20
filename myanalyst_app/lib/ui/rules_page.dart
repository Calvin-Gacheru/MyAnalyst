import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_controller.dart';
import '../theme/tokens.dart';
import 'common.dart';

class RulesPage extends StatefulWidget {
  const RulesPage({super.key});

  @override
  State<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends State<RulesPage> {
  final _input = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final app = AppScope.read(context);
    final error = await app.addRule(_input.text);
    if (!mounted) return;
    setState(() => _error = error);
    if (error == null) {
      _input.clear();
      showMessage(context, app.strings.ruleAdded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    final examples = s.ruleExamples;

    return PageFrame(
      maxWidth: 780,
      children: [
        PageHeader(eyebrow: s.rulesEyebrow, title: s.rulesTitle, subtitle: s.rulesLead),
        Sheet(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.addRule, style: Txt.label),
              const SizedBox(height: Space.sm),
              TextField(
                controller: _input,
                enabled: !app.addingRule,
                minLines: 2,
                maxLines: 4,
                maxLength: AppController.maxRuleLength,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                style: Txt.body.copyWith(fontSize: 15),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: InputDecoration(
                  hintText: '${s.zh ? '例如：' : 'e.g. '}${examples.first}',
                  counterText: '',
                  errorText: _error,
                ),
              ),
              const SizedBox(height: Space.md),
              Row(children: [
                FilledButton(
                  onPressed: app.addingRule ? null : _add,
                  child: Text(app.addingRule ? s.adding : s.addRuleButton),
                ),
                const SizedBox(width: Space.md),
                Expanded(child: Text(s.rulesCantEdit, style: Txt.caption)),
              ]),
              const SizedBox(height: Space.lg),
              Text(s.examples, style: Txt.eyebrow),
              const SizedBox(height: Space.xs),
              Wrap(
                spacing: Space.xs,
                runSpacing: Space.xs,
                children: [
                  for (final e in examples)
                    ActionChip(
                      label: Text(e, style: Txt.caption.copyWith(color: Palette.ink)),
                      backgroundColor: Palette.paper,
                      side: const BorderSide(color: Palette.rule),
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radii.md)),
                      onPressed: () {
                        _input.text = e;
                        _input.selection = TextSelection.collapsed(offset: e.length);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        SectionHeading(s.currentRules, meta: app.rules.isEmpty ? null : '${app.rules.length}'),
        if (app.rulesLoading && app.rules.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Space.lg),
            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.6)),
          )
        else if (app.rulesError != null)
          Row(children: [
            Expanded(child: Text(app.rulesError!, style: Txt.body.copyWith(color: Palette.brick))),
            TextButton(onPressed: app.loadRules, child: Text(s.retry)),
          ])
        else if (app.rules.isEmpty)
          Text(s.noRules, style: Txt.bodyMuted)
        else
          Column(children: [
            for (var i = 0; i < app.rules.length; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 36,
                      child: Text((i + 1).toString().padLeft(2, '0'), style: Txt.monoSmall.copyWith(color: Palette.accent)),
                    ),
                    Expanded(child: SelectableText(app.rules[i].text, style: Txt.body.copyWith(fontSize: 15))),
                    const SizedBox(width: Space.md),
                    Text(s.added(fmtTime(app.rules[i].createdAt)), style: Txt.caption),
                  ],
                ),
              ),
              const Divider(),
            ],
          ]),
      ],
    );
  }
}
