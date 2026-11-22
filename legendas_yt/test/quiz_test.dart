import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:legendas_yt/src/app/services.dart';
import 'package:legendas_yt/src/data/prefs.dart';
import 'package:legendas_yt/src/quiz/quiz_session.dart';
import 'package:legendas_yt/src/quiz/speaker.dart';
import 'package:legendas_yt/src/ui/archived_page.dart';
import 'package:legendas_yt/src/ui/results_page.dart';
import 'package:legendas_yt/src/ui/quiz_page.dart';
import 'package:legendas_yt/src/ui/theme.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_api.dart';
import 'fake_voice.dart';

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
      expect(fake.answers, [('you', true), ('dad', false), ('dad', true)], reason: 'cada resposta vai para o ranking');
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

  group('Repita esta frase', () {
    late FakeApi fake;
    late Prefs prefs;
    late FakeVoice voice;
    late QuizSession quiz;

    setUp(() {
      fake = FakeApi()..quizItems = List.of(sampleQuiz);
      prefs = Prefs(fake.api());
      voice = FakeVoice();
      quiz = QuizSession(api: fake.api(), prefs: prefs, lessonSize: 2, voice: voice, speakShare: 1);
    });

    Future<void> say(List<String> transcripts) async {
      voice.script.add(transcripts);
      await quiz.listen();
      await pumpEventQueue();
    }

    test('falou certo: passa e guarda onde o quiz parou; vale a transcrição mais parecida', () async {
      await quiz.start();
      expect(quiz.exercise, Exercise.speak);
      expect(quiz.canCheck, isFalse, reason: 'falar não tem VERIFICAR');
      await say(['I loved you', 'I love you']);
      expect(quiz.correct, isTrue);
      expect((quiz.speech!.percent, quiz.hearing, quiz.listening), (100, 'I love you', false));
      expect(prefs.quizPos, 1);
    });

    test('três tentativas: "quase" nas duas primeiras; errou, a frase volta no fim', () async {
      await quiz.start();
      await say(['I like food']);
      expect((quiz.correct, quiz.tries), (null, 1));
      expect(quiz.note, startsWith('Quase!'));
      expect([for (final w in quiz.speech!.words) w.heard], [true, false, false]);
      await say(['I glove shoe']);
      expect(quiz.note, contains('tentativa 3 de 3'));
      await say(['hi']);
      expect(quiz.correct, isFalse);
      expect(prefs.quizPos, 0);
      await pumpEventQueue();
      expect(fake.answers, [('you', false)], reason: 'só o resultado final, não cada tentativa');
      quiz.next();
      await say(['my dad']);
      expect(quiz.correct, isTrue);
      quiz.next();
      expect((quiz.current!.word, quiz.exercise, quiz.tries), ('you', Exercise.speak, 0), reason: 'voltou no fim');
    });

    test('nada ouvido não conta tentativa; erro do microfone vira aviso', () async {
      await quiz.start();
      await say([]);
      expect(quiz.tries, 0);
      expect(quiz.note, startsWith('Não ouvi nada'));
      voice.script.add('O microfone está ocupado. Tente de novo.');
      await quiz.listen();
      await pumpEventQueue();
      expect((quiz.note, quiz.listening, quiz.exercise), ('O microfone está ocupado. Tente de novo.', false, Exercise.speak));
    });

    test('parar de ouvir; ouvir a frase de novo desliga o microfone', () async {
      await quiz.start();
      await quiz.listen();
      expect(quiz.listening, isTrue);
      await quiz.stopListening();
      expect(quiz.listening, isFalse);
      expect(quiz.note, startsWith('Não ouvi nada'));
      await quiz.listen();
      quiz.cancelListening();
      expect((quiz.listening, voice.cancels), (false, 1));
    });

    test('"não posso falar agora": vira traduzir, e as lições seguintes também, por um tempo', () async {
      await quiz.start();
      quiz.cantSpeakNow();
      expect((quiz.exercise, voice.available), (Exercise.translate, false));
      for (final w in ['Eu', 'te', 'amo']) {
        quiz.pick(quiz.current!.tiles.indexOf(w));
      }
      quiz.check();
      quiz.next();
      expect(quiz.exercise, Exercise.translate, reason: 'o resto da lição também');
      await quiz.start();
      expect(quiz.exercise, Exercise.translate, reason: 'pausado por ${QuizSession.quietFor.inMinutes} minutos');
      voice.pausedUntil = DateTime.now().subtract(const Duration(seconds: 1));
      await quiz.start();
      expect(quiz.exercise, Exercise.speak, reason: 'passou o tempo');
    });

    test('sem permissão do microfone: as lições seguem sem falar', () async {
      voice.allowed = false;
      await quiz.start();
      await quiz.listen();
      expect(quiz.exercise, Exercise.translate);
      expect(quiz.note, startsWith('Sem acesso ao microfone'));
      expect(voice.blocked, isTrue);
      await quiz.start();
      expect(quiz.exercise, Exercise.translate);
    });

    test('o sorteio mistura os exercícios; sem microfone, só traduzir', () async {
      final kinds = <Exercise>{};
      final mixed = QuizSession(api: fake.api(), prefs: prefs, voice: voice, speakShare: 0.5, random: Random(3));
      for (var i = 0; i < 12; i++) {
        await mixed.start();
        kinds.add(mixed.exercise);
      }
      expect(kinds, {Exercise.translate, Exercise.speak});
      final silent = QuizSession(api: fake.api(), prefs: prefs, speakShare: 1);
      await silent.start();
      expect(silent.exercise, Exercise.translate);
    });
  });

  group('Arquivar frases', () {
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

    test('a frase arquivada sai da lição, sem contar resposta, e não volta mais', () async {
      await quiz.start();
      final turn = quiz.turn;
      expect(await quiz.archiveCurrent(), isTrue);
      expect(fake.archived, {100});
      expect((quiz.current!.word, quiz.answered, quiz.step), ('dad', 0, 0));
      expect(quiz.turn, isNot(turn), reason: 'frase nova na tela: ela é lida');
      answer(['meu', 'pai']);
      expect(prefs.quizPos, 2);
      quiz.next();
      expect(quiz.finished, isTrue);
      prefs.quizPos = 0;
      await quiz.start();
      expect(quiz.current!.word, 'dad', reason: 'do começo, a arquivada não aparece');
    });

    test('arquivar depois de errar: a resposta fica na tela e a frase não volta no fim', () async {
      await quiz.start();
      answer(['pai']);
      expect(await quiz.archiveCurrent(), isTrue);
      expect(quiz.correct, isFalse);
      quiz.next();
      answer(['meu', 'pai']);
      quiz.next();
      expect(quiz.finished, isTrue, reason: '"you" não voltou no fim');
    });

    test('arquivar a lição inteira traz a próxima', () async {
      await quiz.start();
      await quiz.archiveCurrent();
      await quiz.archiveCurrent();
      expect(quiz.current!.word, 'my');
      expect(fake.archived, {100, 200});
    });

    test('sem a API, a frase fica e o aviso explica', () async {
      await quiz.start();
      fake.down = true;
      expect(await quiz.archiveCurrent(), isFalse);
      expect(quiz.current!.word, 'you');
      expect(quiz.note, startsWith('Não deu para arquivar: Sem conexão com a API'));
    });
  });

  group('Revisão', () {
    late FakeApi fake;
    late Prefs prefs;
    late QuizSession quiz;

    setUp(() {
      fake = FakeApi()
        ..quizItems = List.of(sampleQuiz)
        ..answers.addAll([('dad', false), ('you', false), ('dad', false)]); // dad errou 2 vezes, you 1
      prefs = Prefs(fake.api());
      quiz = QuizSession(api: fake.api(), prefs: prefs, review: true);
    });

    void answer(List<String> words) {
      for (final w in words) {
        quiz.pick(quiz.current!.tiles.indexOf(w));
      }
      quiz.check();
    }

    test('as erradas ainda não revisadas, as com mais erros antes; onde o quiz parou não muda', () async {
      prefs.quizPos = 1;
      await quiz.start();
      expect(fake.paths, contains('GET /revisao'));
      expect((quiz.current!.word, quiz.current!.review!.wrong, quiz.current!.review!.pending), ('dad', 2, true));
      expect((quiz.reviewTotal, quiz.reviewPending), (2, 2));
      answer(['meu', 'pai']);
      expect(quiz.correct, isTrue);
      quiz.next();
      expect(quiz.current!.word, 'you');
      answer(['Eu', 'te', 'amo']);
      quiz.next();
      expect(quiz.finished, isTrue);
      expect(prefs.quizPos, 1, reason: 'revisar não muda onde o quiz parou');

      await quiz.start();
      expect(quiz.nothingToReview, isTrue, reason: 'as duas foram revisadas (as respostas chegaram antes)');
      expect(quiz.error, isEmpty);
    });
  });

  group('Combine os pares', () {
    late FakeApi fake;
    late Prefs prefs;

    setUp(() {
      fake = FakeApi()
        ..quizItems = List.of(sampleQuiz)
        ..wordTranslations.addAll({'you': 'você', 'dad': 'pai', 'my': 'meu'});
      prefs = Prefs(fake.api());
    });

    test('a lição ganha um cartão com as palavras dela; o par errado conta erro nas duas', () async {
      final quiz = QuizSession(api: fake.api(), prefs: prefs, random: Random(1));
      await quiz.start();
      var skipped = 0;
      while (quiz.exercise != Exercise.match) {
        for (final w in quiz.current!.answer) {
          quiz.pick(quiz.current!.tiles.indexOf(w));
        }
        quiz.check();
        quiz.next();
        skipped++;
      }
      expect(skipped, inInclusiveRange(1, 3), reason: 'nunca no começo da lição');
      expect(quiz.current, isNull);
      expect({for (final p in quiz.pairs) p.word}, {'you', 'dad', 'my'});
      int pair(String word) => quiz.pairs.indexWhere((p) => p.word == word);

      quiz
        ..pickLeft(pair('you'))
        ..pickRight(pair('dad')); // errado
      expect(quiz.wrongPair, (pair('you'), pair('dad')));
      expect(quiz.matched, isEmpty);
      expect(quiz.missed, {pair('you'), pair('dad')});
      quiz
        ..pickRight(pair('you'))
        ..pickLeft(pair('you')) // a ordem não importa
        ..pickLeft(pair('dad'))
        ..pickRight(pair('dad'));
      expect(quiz.correct, isNull);
      quiz
        ..pickLeft(pair('my'))
        ..pickRight(pair('my'));
      expect(quiz.correct, isTrue);
      expect(quiz.right, skipped, reason: 'com erro, o cartão não soma acerto');
      await pumpEventQueue();
      expect(fake.answers.skip(fake.answers.length - 3).toSet(), {('you', false), ('dad', false), ('my', true)});
      quiz.dispose();
    });

    test('sem 3 traduções diferentes, ou desligado, a lição segue sem o cartão', () async {
      fake.wordTranslations
        ..clear()
        ..addAll({'you': 'você', 'dad': 'você', 'my': 'my'}); // repetida e igual ao inglês
      final quiz = QuizSession(api: fake.api(), prefs: prefs, random: Random(1));
      await quiz.start();
      expect(fake.paths, contains('GET /pares'));
      final off = QuizSession(api: fake.api(), prefs: prefs, matching: false);
      fake.requests.clear();
      await off.start();
      expect(fake.paths, isNot(contains('GET /pares')));
      for (final q in [quiz, off]) {
        var cards = 0;
        while (q.current != null) {
          expect(q.exercise, isNot(Exercise.match));
          q.pick(0);
          q.check();
          q.next();
          if (++cards > 10) break;
        }
        q.dispose();
      }
    });
  });

  Future<AppServices> quizServices(WidgetTester tester, {FakeApi? api}) async {
    final dir = Directory.systemTemp.createTempSync('legendas_quiz');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/servidor.json').writeAsStringSync('{"url": "$apiUrl", "chave": ""}');
    final fake = api ?? (FakeApi()..quizItems = List.of(sampleQuiz));
    final services = (await tester.runAsync(() => AppServices.create(dir: dir, client: fake.client)))!;
    tester.view
      ..physicalSize = const Size(1206, 2622) // um iPhone
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    return services;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('repita esta frase: o microfone ouve, confere e mostra a pronúncia', (tester) async {
    final services = await quizServices(tester);
    final voice = FakeVoice()..script.add(['I love you']);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: QuizPage(services: services, speaker: SilentSpeaker(), voice: voice, speakShare: 1),
    ));
    await settle(tester);
    expect(find.text('Repita esta frase:'), findsOneWidget);
    expect(find.text('NÃO POSSO FALAR AGORA'), findsOneWidget);

    await tester.tap(find.byTooltip('Falar'));
    await settle(tester);
    expect(find.text('Pronúncia perfeita!'), findsOneWidget);
    expect(find.text('Significa: Eu te amo'), findsOneWidget);
    expect(find.text('Pronúncia: 100%'), findsOneWidget);

    await tester.tap(find.text('CONTINUAR'));
    await settle(tester);
    expect(find.text('Repita esta frase:'), findsOneWidget);
    await tester.tap(find.text('NÃO POSSO FALAR AGORA'));
    await tester.pump();
    expect(find.text('Traduza esta frase:'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tela do quiz: lê a frase, monta com as fichas, confere e continua', (tester) async {
    final services = await quizServices(tester);
    final speaker = SilentSpeaker();

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: QuizPage(services: services, speaker: speaker, voice: FakeVoice(), speakShare: 0),
    ));
    await settle(tester);
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

  testWidgets('arquivar pergunta antes; Cancelar não arquiva', (tester) async {
    final fake = FakeApi()..quizItems = List.of(sampleQuiz);
    final services = await quizServices(tester, api: fake);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: QuizPage(services: services, speaker: SilentSpeaker(), voice: FakeVoice(), speakShare: 0),
    ));
    await settle(tester);

    await tester.tap(find.byTooltip('Arquivar esta frase'));
    await settle(tester);
    expect(find.text('Arquivar esta frase?'), findsOneWidget);
    expect(find.textContaining('“I love you”'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await settle(tester);
    expect(fake.archived, isEmpty);
    expect(find.text('PALAVRA FREQUENTE Nº 1'), findsOneWidget);

    await tester.tap(find.byTooltip('Arquivar esta frase'));
    await settle(tester);
    await tester.tap(find.text('Arquivar'));
    await settle(tester);
    expect(fake.archived, {100});
    expect(find.text('PALAVRA FREQUENTE Nº 2'), findsOneWidget);
    expect(find.text('Frase arquivada: ela não aparece mais nas lições.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('frases arquivadas: a lista e restaurar', (tester) async {
    final fake = FakeApi()
      ..quizItems = List.of(sampleQuiz)
      ..archived.addAll({100, 300});
    final services = await quizServices(tester, api: fake);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: ArchivedPage(services: services)));
    await settle(tester);
    expect(find.textContaining('2 frases ficam fora das lições'), findsOneWidget);
    expect(find.text('I love you'), findsOneWidget);
    expect(find.text('my dog'), findsOneWidget);
    expect(find.text('Vídeo A · arquivada em 22/11/2026'), findsNWidgets(2));

    await tester.tap(find.text('Restaurar').first);
    await settle(tester);
    expect(fake.archived, {300});
    expect(find.text('I love you'), findsNothing);
    expect(find.text('Frase restaurada: ela volta a aparecer nas lições.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('seus resultados: os totais, as mais erradas primeiro e as outras ordens', (tester) async {
    final fake = FakeApi()..quizItems = List.of(sampleQuiz);
    fake.answers.addAll([('you', true), ('dad', false), ('you', false), ('my', true), ('dad', false), ('you', true)]);
    final services = await quizServices(tester, api: fake);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: ResultsPage(services: services)));
    await settle(tester);
    expect(find.text('50%'), findsOneWidget, reason: '3 acertos e 3 erros');
    expect(find.textContaining('3 palavras testadas'), findsOneWidget);
    double y(String word) => tester.getTopLeft(find.text(word)).dy;

    expect(find.text('my'), findsNothing, reason: 'mais erradas: só as que já foram erradas');
    expect(find.byType(ColoredBox), findsWidgets, reason: 'a barra de acertos e erros');
    expect(y('dad'), lessThan(y('you')), reason: 'dad errou 2 vezes, you 1');
    expect(find.text('✗ 2'), findsOneWidget);

    await tester.tap(find.text('Acertadas'));
    await tester.pump();
    expect(find.text('dad'), findsNothing);
    expect(y('you'), lessThan(y('my')));

    await tester.tap(find.text('Recentes'));
    await tester.pump();
    expect(y('you'), lessThan(y('dad')));
    expect(y('dad'), lessThan(y('my')), reason: 'o teste mais recente primeiro');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('revisar: o botão nos resultados abre a revisão, com o histórico da palavra', (tester) async {
    final fake = FakeApi()
      ..quizItems = List.of(sampleQuiz)
      ..answers.addAll([('dad', false), ('dad', false), ('you', true)]);
    final services = await quizServices(tester, api: fake);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: ResultsPage(services: services)));
    await settle(tester);
    expect(find.text('REVISAR 1 PALAVRA'), findsOneWidget);
    expect(find.textContaining('Primeiro a errada que você ainda não revisou'), findsOneWidget);

    await tester.tap(find.text('REVISAR 1 PALAVRA'));
    await settle(tester);
    expect(find.text('REVISÃO · AINDA NÃO REVISADA'), findsOneWidget);
    expect(find.textContaining('"dad": você errou 2 de 2 vezes'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('combine os pares: uma de cada lado; o certo apaga, o errado pisca, e a palavra é lida', (tester) async {
    final fake = FakeApi()
      ..quizItems = List.of(sampleQuiz)
      ..wordTranslations.addAll({'you': 'você', 'dad': 'pai', 'my': 'meu'});
    final services = await quizServices(tester, api: fake);
    final speaker = SilentSpeaker();
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: QuizPage(services: services, speaker: speaker, voice: FakeVoice(), speakShare: 0, matchAt: 0),
    ));
    await settle(tester);
    expect(find.text('Combine os pares:'), findsOneWidget);

    await tester.tap(find.text('você'));
    await tester.pump();
    await tester.tap(find.text('dad'));
    await tester.pump();
    expect(speaker.said, ['dad'], reason: 'tocar na palavra em inglês lê a palavra');
    await tester.pump(const Duration(milliseconds: 800)); // o vermelho passa
    for (final (pt, en) in [('você', 'you'), ('pai', 'dad'), ('meu', 'my')]) {
      await tester.tap(find.text(pt));
      await tester.pump();
      await tester.tap(find.text(en));
      await tester.pump();
    }
    expect(find.text('Pares combinados!'), findsOneWidget);
    expect(find.textContaining('Errou os pares de'), findsOneWidget);

    await tester.tap(find.text('CONTINUAR'));
    await settle(tester);
    expect(find.text('PALAVRA FREQUENTE Nº 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
