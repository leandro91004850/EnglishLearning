import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legendas_yt/src/app/session.dart';
import 'package:legendas_yt/src/core/cue.dart';
import 'package:legendas_yt/src/core/subtitles.dart';
import 'package:legendas_yt/src/data/history.dart';
import 'package:legendas_yt/src/ui/widgets/transcript_list.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_api.dart';

/// Uma sessão já com a legenda carregada: 600 falas, umas curtas e outras
/// longas (alturas bem diferentes na lista).
SubtitleSession loadedSession(Directory dir) {
  final api = FakeApi().api();
  final s = SubtitleSession(api: api, history: History(api));
  final cues = [
    for (var i = 0; i < 600; i++)
      Cue(i * 3.0, 3, i % 7 == 0 ? 'fala $i ${'muito comprida ' * 12}' : 'fala $i'),
  ];
  s
    ..videoId = 'abcdefghijk'
    ..meta = SubtitleMeta(
      cues: cues,
      sourceName: 'English',
      sourceCode: 'en',
      generated: false,
      target: 'pt',
      targetName: 'Português',
    )
    ..translations = [for (final c in cues) 'tradução de ${c.text.split(' ').take(2).join(' ')}'];
  return s;
}

Future<void> pumpList(WidgetTester tester, SubtitleSession session, ValueNotifier<int> current) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: TranscriptList(session: session, current: current, onSeek: (_) {}, onRetry: () {}),
    ),
  ));
}

void expectOnScreen(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(finder, findsOneWidget);
  final rect = tester.getRect(finder);
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(rect.top >= 0 && rect.bottom <= screen.height, isTrue, reason: '"$text" em $rect');
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('legendas_list'));
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('acompanha o vídeo até uma fala distante', (tester) async {
    final current = ValueNotifier(-1);
    await pumpList(tester, loadedSession(dir), current);
    await tester.pump();

    current.value = 450;
    await tester.pumpAndSettle();
    expectOnScreen(tester, 'fala 451'); // a 450 é longa; a de baixo também aparece

    current.value = 37;
    await tester.pumpAndSettle();
    expectOnScreen(tester, 'fala 37');
  });

  testWidgets('ao aparecer, já mostra a fala atual (reabrir o app)', (tester) async {
    final current = ValueNotifier(523);
    await pumpList(tester, loadedSession(dir), current);
    await tester.pumpAndSettle();
    expectOnScreen(tester, 'fala 523');
  });
}
