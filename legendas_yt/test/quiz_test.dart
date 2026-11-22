import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legendas_yt/src/app/services.dart';
import 'package:legendas_yt/src/data/prefs.dart';
import 'package:legendas_yt/src/quiz/quiz_session.dart';
import 'package:legendas_yt/src/quiz/speaker.dart';
import 'package:legendas_yt/src/ui/quiz_page.dart';
import 'package:legendas_yt/src/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_api.dart';

void main() {
  group('QuizSession', () {
    late FakeApi fake;
    late Prefs prefs;
    late QuizSession quiz;

    setUp(() {
      fake = FakeApi()..quizItems = List.of(sampleQuiz);
      prefs = Prefs(fake.api());
      quiz = QuizSession(api: fake.api(), prefs: prefs, lessonSize: 2);
    });

    void answer(List<String> words) {
      for (final w in words) {
        quiz.pick(quiz.current!.tiles.indexOf(w));
      }
      quiz.check();
    }

    test('lição de onde o quiz parou; acertar avança, a errada volta no fim', () async {
      await quiz.start();
      expect((quiz.total, quiz.current!.word), (3, 'you'));
      expect(quiz.canCheck, isFalse, reason: 'nenhuma ficha escolhida');
      answer(['Eu', 'te', 'amo']);
      expect(quiz.correct, isTrue);
      expect(prefs.quizPos, 1);
      quiz.next();

      answer(['pai', 'meu']);
      expect(quiz.correct, isFalse);
      expect(prefs.quizPos, 1, reason: 'errou: o quiz não avança');
      quiz.next();
      expect(quiz.current!.word, 'dad', reason: 'a frase errada volta no fim da lição');
      answer(['meu', 'pai']);
      expect(quiz.correct, isTrue);
      quiz.next();

      expect(quiz.finished, isTrue);
      expect((quiz.right, quiz.answered), (2, 3));
      await pumpEventQueue();
      expect(fake.prefs['quizPos'], 2, reason: 'onde o quiz parou foi para a API');
      await quiz.start();
      expect(quiz.current!.word, 'my', reason: 'a próxima lição começa de onde parou');
    });

    test('tirar uma ficha da resposta; maiúsculas não contam', () async {
      await quiz.start();
      final eu = quiz.current!.tiles.indexOf('Eu');
      quiz
        ..pick(eu)
        ..pick(eu); // a mesma ficha não entra duas vezes
      expect(quiz.picked, [eu]);
      quiz.unpick(eu);
      expect(quiz.picked, isEmpty);
      answer(['Eu', 'te', 'amo']);
      expect(quiz.correct, isTrue);
      final before = List.of(quiz.picked);
      quiz.pick(quiz.current!.tiles.indexOf('pai'));
      expect(quiz.picked, before, reason: 'depois de conferir, as fichas não mexem');
    });

    test('praticar uma palavra escolhida não muda onde o quiz parou', () async {
      await quiz.start(at: 2);
      expect(quiz.current!.word, 'my');
      answer(['meu', 'cachorro']);
      expect(quiz.correct, isTrue);
      expect(prefs.quizPos, 0);
    });

    test('quiz todo feito, sem frases e API fora do ar', () async {
      prefs.quizPos = 3;
      await quiz.start();
      expect(quiz.completedAll, isTrue);

      fake.quizItems = [];
      prefs.quizPos = 0;
      await quiz.start();
      expect(quiz.error, startsWith('Ainda não há frases traduzidas'));

      fake.down = true;
      await quiz.start();
      expect(quiz.error, startsWith('Sem conexão com a API'));
    });
  });

  testWidgets('tela do quiz: lê a frase, monta com as fichas, confere e continua', (tester) async {
    final dir = Directory.systemTemp.createTempSync('legendas_quiz');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/servidor.json').writeAsStringSync('{"url": "$apiUrl", "chave": ""}');
    final fake = FakeApi()..quizItems = List.of(sampleQuiz);
    final services = (await tester.runAsync(() => AppServices.create(dir: dir, client: fake.client)))!;
    final speaker = SilentSpeaker();
    tester.view
      ..physicalSize = const Size(1206, 2622) // um iPhone
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: QuizPage(services: services, speaker: speaker)));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('Traduza esta frase:'), findsOneWidget);
    expect(find.text('PALAVRA FREQUENTE Nº 1'), findsOneWidget);
    expect(find.text('"you" aparece 99 vezes nas suas legendas'), findsOneWidget);
    expect(speaker.said, ['I love you'], reason: 'a frase é lida quando aparece');

    await tester.tap(find.text('Eu'));
    await tester.pump();
    await tester.tap(find.text('te'));
    await tester.pump();
    await tester.tap(find.text('amo'));
    await tester.pump();
    await tester.tap(find.text('VERIFICAR'));
    await tester.pump();
    expect(find.text('Muito bem!'), findsOneWidget);
    expect(find.text('Ver no vídeo: Vídeo A'), findsOneWidget);

    await tester.tap(find.text('CONTINUAR'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('PALAVRA FREQUENTE Nº 2'), findsOneWidget);
    expect(speaker.said, ['I love you', 'my dad']);
    await tester.pumpWidget(const SizedBox());
  });
}
