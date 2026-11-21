import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:legendas_yt/src/app/session.dart';
import 'package:legendas_yt/src/core/cue.dart';
import 'package:legendas_yt/src/core/subtitles.dart';
import 'package:legendas_yt/src/data/banco.dart';
import 'package:legendas_yt/src/data/history.dart';
import 'package:legendas_yt/src/data/translation_cache.dart';
import 'package:legendas_yt/src/translation/translator.dart';
import 'package:legendas_yt/src/youtube/transcript_api.dart';

import 'fake_banco.dart';
import 'helpers.dart';

void main() {
  late Directory dir;
  late FakeYouTube yt;
  late List<String> googleBatches; // primeira fala de cada lote que foi ao Google
  late SubtitleSession session;
  late History history;

  SubtitleSession build({required http.Client translate, Banco? banco}) {
    history = History(File('${dir.path}/historico.json'));
    return SubtitleSession(
      history: history,
      cache: TranslationCache(Directory('${dir.path}/cache')),
      transcripts: TranscriptApi(client: yt.client),
      translation: TranslationService(client: translate),
      client: MockClient((req) async => http.Response(
            jsonEncode({'title': 'Um vídeo', 'author_name': 'Um canal'}),
            200,
          )),
      banco: banco,
    );
  }

  /// Google que "traduz" pondo cada fala em maiúsculas.
  http.Client upperGoogle() => MockClient((req) async {
        final q = req.url.queryParameters['q']!;
        final lines = q.split('\n');
        googleBatches.add(lines.first);
        return http.Response.bytes(
          utf8.encode(jsonEncode([
            [
              for (var i = 0; i < lines.length; i++)
                [i < lines.length - 1 ? '${lines[i].toUpperCase()}\n' : lines[i].toUpperCase(), lines[i]],
            ],
          ])),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

  setUp(() {
    dir = Directory.systemTemp.createTempSync('legendas_session');
    googleBatches = [];
    yt = FakeYouTube(
      player: playerResponse(tracks: [captionTrack('en', name: 'English'), captionTrack('en', asr: true)]),
      // a terceira só tem espaços: fica na lista, vazia, e não vai para o tradutor
      xml: transcriptXml([(1, 2, 'hello\nthere'), (3, 2, 'how are you'), (5, 1, ' \n ')]),
    );
  });
  tearDown(() {
    session.dispose();
    dir.deleteSync(recursive: true);
  });

  test('busca a legenda, traduz e guarda no cache', () async {
    session = build(translate: upperGoogle());
    final r = session.load('https://youtu.be/abcdefghijk?si=x');
    expect(r.ok, isTrue);
    expect(r.videoId, 'abcdefghijk');
    await eventually(() => !session.busy);

    expect(session.cues.map((c) => c.text), ['hello there', 'how are you', '']);
    expect(session.translations, ['HELLO THERE', 'HOW ARE YOU', null]);
    expect(session.status, 'English → Português ✓ (Google)');
    expect(session.statusError, isFalse);
    expect(session.meta!.generated, isFalse);
    expect(googleBatches, hasLength(1));

    // título pelo oEmbed
    await eventually(() => history.find('abcdefghijk')!.title.isNotEmpty);
    expect(history.find('abcdefghijk')!.author, 'Um canal');

    // de novo: vem do cache, sem pedir nada
    final before = yt.requests.length;
    session.load('abcdefghijk');
    await eventually(() => !session.busy);
    expect(session.translations, ['HELLO THERE', 'HOW ARE YOU', null]);
    expect(yt.requests.length, before);
    expect(googleBatches, hasLength(1));
  });

  test('traduz primeiro o trecho onde o vídeo está', () async {
    yt.xml = transcriptXml([for (var i = 0; i < 100; i++) (i * 2.0, 2.0, 'line $i')]);
    session = build(translate: upperGoogle());
    session.load('abcdefghijk');
    session.focus(session.job, 85); // o vídeo está na fala 85
    await eventually(() => !session.busy);
    // lotes de 40 falas: [0-39], [40-79], [80-99] -> começa pelo que tem a 85
    expect(googleBatches, ['line 80', 'line 0', 'line 40']);
    expect(session.translations.every((t) => t != null && t.startsWith('LINE')), isTrue);
  });

  test('erros viram as mensagens do app.py', () async {
    yt.player = playerResponse();
    session = build(translate: upperGoogle());
    session.load('abcdefghijk');
    await eventually(() => !session.busy);
    expect(session.status, 'Este vídeo não tem legendas (nem automáticas).');
    expect(session.statusError, isTrue);

    expect(session.load('não é um link').error, 'Link do YouTube inválido.');
  });

  test('source "pt" prefere a faixa em português e traduz para inglês', () async {
    yt.player = playerResponse(tracks: [captionTrack('en', name: 'English'), captionTrack('pt', asr: true)]);
    session = build(translate: upperGoogle());
    session.load('abcdefghijk', source: 'pt');
    await eventually(() => !session.busy);
    expect(session.meta!.sourceCode, 'pt');
    expect(session.meta!.target, 'en');
    expect(session.status, 'pt → English ✓ (Google)');
  });

  group('com o banco de dados', () {
    test('legenda que o banco já tem: sem YouTube, e só traduz o que falta', () async {
      final db = FakeBanco()
        ..stored = SavedTrack(
          id: 42,
          db: 0,
          meta: const SubtitleMeta(
            cues: [Cue(1, 2, 'hello there'), Cue(3, 2, 'how are you')],
            sourceName: 'English',
            sourceCode: 'en',
            generated: false,
            target: 'pt',
            targetName: 'Português',
          ),
          translations: [(0, 'olá')],
        );
      session = build(translate: upperGoogle(), banco: db);
      session.load('abcdefghijk');
      await eventually(() => !session.busy);
      await db.flush();

      expect(yt.requests, isEmpty, reason: 'a legenda veio do banco');
      expect(session.translations, ['olá', 'HOW ARE YOU']);
      expect(googleBatches, ['how are you']);
      expect(db.translationsSaved, [(1, 'HOW ARE YOU')]);
      expect(session.status, 'English → Português ✓ (Google + banco de dados)');
    });

    test('tudo traduzido no banco: nem o tradutor é chamado', () async {
      final db = FakeBanco()
        ..stored = SavedTrack(
          id: 42,
          db: 0,
          meta: const SubtitleMeta(
            cues: [Cue(1, 2, 'hello')],
            sourceName: 'English',
            sourceCode: 'en',
            generated: true,
            target: 'pt',
            targetName: 'Português',
          ),
          translations: [(0, 'olá')],
        );
      session = build(translate: upperGoogle(), banco: db);
      session.load('abcdefghijk');
      await eventually(() => !session.busy);
      expect(googleBatches, isEmpty);
      expect(session.status, 'English → Português ✓ (banco de dados)');
    });

    test('legenda nova: vem do YouTube e vai para o banco, com as traduções', () async {
      final db = FakeBanco();
      session = build(translate: upperGoogle(), banco: db);
      session.load('abcdefghijk', source: 'en');
      await eventually(() => !session.busy);
      await db.flush();
      expect(db.calls, [
        'findTranscript',
        'findTrack',
        'saveTranscript abcdefghijk en 3',
        'saveTranslations 7',
      ]);
      expect(db.translationsSaved, [(0, 'HELLO THERE'), (1, 'HOW ARE YOU')]);
      expect(session.status, 'English → Português ✓ (Google)');
    });

    test('legenda já traduzida só no aparelho vai para o banco', () async {
      final db = FakeBanco();
      session = build(translate: upperGoogle(), banco: db);
      session.load('abcdefghijk');
      await eventually(() => !session.busy);
      await db.flush();
      db.calls.clear();

      session.load('abcdefghijk'); // de novo: vem do cache do aparelho
      await eventually(() => !session.busy);
      await db.flush();
      expect(db.calls, ['storeComplete abcdefghijk 2']);
    });
  });
}
