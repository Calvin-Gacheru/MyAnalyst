// Renders each screen to PNG for visual review:
//   flutter test test/screens_golden_test.dart --update-goldens
// Output lands in test/goldens/.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myanalyst_app/data/mock_repository.dart';
import 'package:myanalyst_app/i18n/strings.dart';
import 'package:myanalyst_app/main.dart';
import 'package:myanalyst_app/models/models.dart';
import 'package:myanalyst_app/state/app_controller.dart';

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await loader.load();
  }

  const d = 'assets/fonts';
  await family('Plex Sans', ['$d/IBMPlexSans-Regular.ttf', '$d/IBMPlexSans-Medium.ttf', '$d/IBMPlexSans-SemiBold.ttf']);
  await family('Plex Serif', ['$d/IBMPlexSerif-Regular.ttf', '$d/IBMPlexSerif-Medium.ttf', '$d/IBMPlexSerif-Italic.ttf']);
  await family('Plex Mono', ['$d/IBMPlexMono-Regular.ttf']);
  await family('Noto Sans SC', ['$d/NotoSansSC-Regular-subset.ttf']);
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    await family('MaterialIcons', ['$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
  }
}

Dataset _dataset(String key, {bool zh = false}) {
  final j = (jsonDecode(File('assets/mock/${key}_upload.json').readAsStringSync()) as Map).cast<String, Object?>();
  if (zh) {
    j['executive_summary'] = j['executive_summary_zh'] ?? j['executive_summary'];
    j['data_dictionary'] = j['data_dictionary_zh'] ?? j['data_dictionary'];
  }
  // Fixed so the "Analysed ... at ..." line doesn't change the goldens every minute.
  return Dataset.fromUploadJson(j, fileName: '$key.csv', uploadedAt: DateTime(2026, 10, 19, 9, 30));
}

final _askedAt = DateTime(2026, 10, 19, 9, 42);

Answer _answer(String key, {bool zh = false}) {
  final j = ((jsonDecode(File('assets/mock/answers.json').readAsStringSync()) as Map)[key] as Map).cast<String, Object?>();
  return Answer.fromJson({...j, if (zh && j['answer_zh'] != null) 'answer': j['answer_zh'], 'session_id': 's'});
}

AppController _controller({Dataset? ds, Section section = Section.overview, bool zh = false, bool signedIn = true}) {
  final c = AppController(MockAnalystRepository(latencyScale: 0), isDemo: true, language: zh ? AppLanguage.zh : AppLanguage.en)
    ..restoring = false
    ..username = signedIn ? 'li.wei' : null
    ..dataset = ds
    ..section = section;
  return c;
}

Future<void> _shoot(WidgetTester tester, AppController c, String name, Size size,
    {double? tallHeight, Future<void> Function(WidgetTester)? before}) async {
  tester.view.physicalSize = Size(size.width, tallHeight ?? size.height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MyAnalystApp(controller: c));
  await tester.pump(const Duration(milliseconds: 400));
  if (before != null) await before(tester);
  await expectLater(find.byType(MyAnalystApp), matchesGoldenFile('goldens/$name.png'));
}

void main() {
  setUpAll(_loadFonts);

  const desktop = Size(1440, 900);
  const phone = Size(390, 844);

  testWidgets('auth phone', (t) => _shoot(t, _controller(signedIn: false), 'auth_phone', phone));
  testWidgets('auth phone zh', (t) => _shoot(t, _controller(signedIn: false, zh: true), 'auth_phone_zh', phone));

  testWidgets('start desktop', (t) async {
    final c = _controller()
      ..library = [
        DatasetSummary.of(_dataset('bakery')),
        DatasetSummary.of(_dataset('coffee')),
      ];
    await _shoot(t, c, 'start_desktop', desktop, tallHeight: 1100);
  });
  testWidgets('start phone zh', (t) => _shoot(t, _controller(zh: true), 'start_phone_zh', phone, tallHeight: 1700));
  testWidgets('lock phone', (t) async {
    final c = _controller(signedIn: false)
      ..locked = true
      ..lockedUser = 'li.wei';
    await _shoot(t, c, 'lock_phone', phone);
  });
  testWidgets('lock phone zh', (t) async {
    final c = _controller(signedIn: false, zh: true)
      ..locked = true
      ..lockedUser = 'li.wei';
    await _shoot(t, c, 'lock_phone_zh', phone);
  });
  testWidgets('biometric offer phone', (t) async {
    final c = _controller()..offerBiometric = true;
    await _shoot(t, c, 'biometric_offer_phone', phone, tallHeight: 1200);
  });

  testWidgets('cash desktop', (t) async {
    await _shoot(t, _controller(ds: _dataset('bakery'), section: Section.cash), 'cash_desktop', desktop, tallHeight: 3000);
  });
  testWidgets('cash phone', (t) async {
    await _shoot(t, _controller(ds: _dataset('bakery'), section: Section.cash), 'cash_phone', phone, tallHeight: 4200,
        before: (t) async {
      // Open the first financing card to show its calculator.
      await t.tap(find.text('Details and calculator').first);
      await t.pump(const Duration(milliseconds: 400));
    });
  });
  testWidgets('cash phone zh', (t) async {
    await _shoot(t, _controller(ds: _dataset('bakery', zh: true), section: Section.cash, zh: true), 'cash_phone_zh', phone,
        tallHeight: 3600);
  });
  testWidgets('overview bakery desktop', (t) async {
    await _shoot(t, _controller(ds: _dataset('bakery')), 'overview_bakery_desktop', desktop, tallHeight: 1700);
  });
  testWidgets('overview coffee phone', (t) async {
    await _shoot(t, _controller(ds: _dataset('coffee')), 'overview_coffee_phone', phone, tallHeight: 3800);
  });
  testWidgets('data desktop zh', (t) async {
    await _shoot(t, _controller(ds: _dataset('bakery', zh: true), section: Section.data, zh: true), 'data_desktop_zh', desktop,
        tallHeight: 1200);
  });
  testWidgets('ask bakery phone', (t) async {
    final c = _controller(ds: _dataset('bakery'), section: Section.ask);
    c.exchanges.addAll([
      Exchange(question: 'Why is my cash going down?', askedAt: _askedAt, answer: _answer('bakery_cash')),
      Exchange(question: 'Where can I cut costs?', askedAt: _askedAt, answer: _answer('bakery_costs')),
    ]);
    await _shoot(t, c, 'ask_bakery_phone', phone, tallHeight: 2000);
  });
  testWidgets('ask thread desktop zh', (t) async {
    final c = _controller(ds: _dataset('coffee', zh: true), section: Section.ask, zh: true);
    c.exchanges.addAll([
      Exchange(question: '哪些饮品最赚钱？', askedAt: _askedAt, answer: _answer('top_products', zh: true)),
      Exchange(question: '能预测下个月的营业额吗？', askedAt: _askedAt, answer: _answer('giveup', zh: true)),
      Exchange(question: '一周中哪天最忙？', askedAt: _askedAt),
    ]);
    await _shoot(t, c, 'ask_thread_desktop_zh', desktop, tallHeight: 1400);
  });
  testWidgets('rules desktop', (t) async {
    final c = _controller(ds: _dataset('bakery'), section: Section.rules);
    c.rules = [
      BusinessRule(id: 1, datasetId: 'x', text: 'Exclude refunds from revenue figures.', createdAt: DateTime(2026, 10, 19, 9, 12)),
    ];
    await _shoot(t, c, 'rules_desktop', desktop);
  });
}
