import 'package:flutter_test/flutter_test.dart';
import 'package:legendas_yt/src/app/session.dart';
import 'package:legendas_yt/src/data/history.dart';

import 'fake_api.dart';

void main() {
  late FakeApi fake;
  late History history;
  late SubtitleSession session;

  setUp(() {
    fake = FakeApi();
    history = History(fake.api());
    session = SubtitleSession(api: fake.api(), history: history, pollEvery: Duration.zero);
  });
  tearDown(() => session.dispose());

  /// Espera a sessão parar de perguntar à API.
  Future<void> settle() async {
    for (var i = 0; i < 200 && session.busy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(session.busy, isFalse, reason: 'a sessão não terminou');
  }

  test('abre na API e acompanha a legenda até ficar pronta', () async {
    fake.jobStates = [
      jobState(message: 'Buscando legendas…'),
      jobState(
        message: 'Traduzindo para Português… 50%',
        withMeta: meta,
        translations: [
          [0, 'Olá'],
        ],
        total: 1,
        title: 'Meu vídeo',
        author: 'Meu canal',
      ),
      jobState(
        message: 'English → Português ✓ (Google)',
        ready: true,
        finished: true,
        translations: [
          [1, 'mundo'],
        ],
        total: 2,
        title: 'Meu vídeo',
      ),
    ];
    final result = session.load('https://youtu.be/aaaaaaaaaaa?t=30');
    expect(result.videoId, 'aaaaaaaaaaa');
    expect(session.busy, isTrue);
    expect(history.items.single.id, 'aaaaaaaaaaa', reason: 'a lista muda na hora, como na API');
    await settle();

    expect(fake.opened.single, {
      'url': 'aaaaaaaaaaa',
      'escolha': 'auto',
      'manter_lugar': false,
      'restaurando': false,
    });
    final polls = [for (final r in fake.requests) if (r.url.path == '/legendas/job1') r.url.queryParameters];
    expect(polls, [
      {'desde': '0', 'falas': 'true'},
      {'desde': '0', 'falas': 'true'}, // as falas ainda não tinham chegado
      {'desde': '1'},
    ]);
    expect(session.cues.map((c) => c.text), ['Hello', 'world', '']);
    expect(session.translations, ['Olá', 'mundo', null]);
    expect((session.translated, session.toTranslate), (2, 2));
    expect(session.status, 'English → Português ✓ (Google)');
    expect(session.statusError, isFalse);
    expect(history.find('aaaaaaaaaaa')!.title, 'Meu vídeo');
  });

  test('link inválido: nem chama a API', () {
    final result = session.load('isto não é um link');
    expect(result.error, 'Link do YouTube inválido.');
    expect(fake.requests, isEmpty);
  });

  test('erro da API e API fora do ar aparecem como erro', () async {
    fake.jobStates = [jobState(message: 'Este vídeo não tem legendas (nem automáticas).', error: true, finished: true)];
    session.load('aaaaaaaaaaa');
    await settle();
    expect(session.status, 'Este vídeo não tem legendas (nem automáticas).');
    expect(session.statusError, isTrue);

    fake.down = true;
    session.load('bbbbbbbbbbb');
    await settle();
    expect(session.status, startsWith('Sem conexão com a API'));
    expect(session.statusError, isTrue);

    fake
      ..down = false
      ..jobStates = []; // a API reiniciou e esqueceu a legenda
    session.load('ccccccccccc');
    await settle();
    expect(session.status, 'Legenda não encontrada: abra o vídeo de novo.');
  });

  test('o mesmo vídeo de novo (troca de idioma) fica no lugar; reabrir ao iniciar avisa a API', () async {
    session.load('aaaaaaaaaaa');
    await settle();
    session.load('aaaaaaaaaaa', source: 'pt');
    await settle();
    session.load('bbbbbbbbbbb', keepPlace: true, restoring: true);
    await settle();
    expect([for (final o in fake.opened) (o['escolha'], o['manter_lugar'], o['restaurando'])], [
      ('auto', false, false),
      ('pt', true, false),
      ('auto', true, true),
    ]);
  });

  test('avisa a API onde o vídeo está, e manda onde ele parou', () async {
    fake.videos = [video('aaaaaaaaaaa')];
    await history.load();
    fake.jobStates = [jobState(message: 'Traduzindo…', withMeta: meta), jobState(finished: true, ready: true)];
    session.load('aaaaaaaaaaa');
    session.focus(session.job, 7);
    session.focus(session.job - 1, 99); // de um job antigo: não vale
    await settle();
    expect(fake.focuses, [7]);

    session.progress('aaaaaaaaaaa', 42.04, 600);
    await history.flush();
    expect(fake.positions, [('aaaaaaaaaaa', 42.0, 600.0)]);
    session.progress('curto', 1, 2);
    session.progress('aaaaaaaaaaa', double.nan, 2);
    await history.flush();
    expect(fake.positions, hasLength(1));
  });

  test('abrir outro vídeo para de acompanhar o anterior', () async {
    fake.jobStates = [jobState(message: 'Traduzindo o primeiro…', withMeta: meta)]; // nunca termina
    session.load('aaaaaaaaaaa');
    await pumpEventQueue();
    fake.jobStates = [jobState(message: 'pronto', ready: true, finished: true)];
    session.load('bbbbbbbbbbb');
    await settle();
    expect(session.videoId, 'bbbbbbbbbbb');
    expect(session.status, 'pronto');
    expect(session.cues, isEmpty, reason: 'as falas do primeiro não aparecem no segundo');
  });
}
