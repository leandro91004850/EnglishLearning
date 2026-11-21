import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legendas_yt/src/core/cue.dart';
import 'package:legendas_yt/src/core/subtitles.dart';
import 'package:legendas_yt/src/data/banco.dart';

/// Um PostgreSQL de mentira: anota cada SQL e responde com [handler].
class FakeDb implements DbConnection, DbSession {
  FakeDb([this.handler]);

  List<List<Object?>> Function(String sql, List<Object?> params)? handler;
  final List<(String, List<Object?>)> log = [];
  bool open = true;
  Object? failNext;

  /// O SQL sem as linhas do esquema (CREATE ...), na ordem.
  List<String> get statements => [
    for (final (sql, _) in log)
      if (!sql.startsWith('CREATE')) sql,
  ];

  List<(String, List<Object?>)> where(String prefix) => [
    for (final e in log)
      if (e.$1.startsWith(prefix)) e,
  ];

  @override
  bool get isOpen => open;

  @override
  Future<T> transaction<T>(Future<T> Function(DbSession session) fn) => fn(this);

  @override
  Future<void> close() async => open = false;

  @override
  Future<List<List<Object?>>> query(String sql, [List<Object?> params = const []]) async {
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
    log.add((sql, params));
    return handler?.call(sql, params) ?? const [];
  }
}

void main() {
  test('splitWords: letras, apóstrofo e hífen; sem números e pontuação', () {
    expect(splitWords("Don't stop, João! It’s well-known"), ["don't", 'stop', 'joão', "it's", 'well-known']);
    expect(splitWords('Rock & roll 2005, 100%... ok?'), ['rock', 'roll', 'ok']);
    expect(splitWords('${'a' * 61} curto'), ['curto']);
    expect(splitWords(null), isEmpty);
  });

  group('.env', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('legendas_env'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('lê CHAVE=valor, ignora comentários e tira aspas', () {
      final f = File('${dir.path}/.env')
        ..writeAsStringSync(
          '﻿# comentário\nDB_HOST = db.local\nexport DB_USER="ana maria"\n'
          "DB_PASSWORD='s3=cr#t'\nLIXO\n\nDB_PORT=6543\n",
        );
      expect(readEnv(f), {'DB_HOST': 'db.local', 'DB_USER': 'ana maria', 'DB_PASSWORD': 's3=cr#t', 'DB_PORT': '6543'});
      expect(readEnv(File('${dir.path}/nao-existe')), isEmpty);
    });

    test('grava trocando só as linhas DB_* e mantém o resto', () {
      final f = File('${dir.path}/.env')..writeAsStringSync('# meu comentário\nOUTRA=1\nDB_HOST=velho\n');
      writeEnv(f, {
        'DB_HOST': 'novo',
        'DB_PORT': '5432',
        'DB_NAME': 'legendas_yt',
        'DB_USER': 'postgres',
        'DB_PASSWORD': ' com espaço ',
      });
      final text = f.readAsStringSync();
      expect(text, startsWith('# meu comentário\nOUTRA=1\nDB_HOST=novo\n'));
      expect(text, contains('DB_PASSWORD=" com espaço "'));
      expect(text, isNot(contains('DB_SSLMODE')));
      expect(readEnv(f)['DB_PASSWORD'], ' com espaço ');

      final novo = File('${dir.path}/sub/.env');
      writeEnv(novo, {'DB_HOST': 'h', 'DB_PASSWORD': ''});
      expect(novo.readAsStringSync(), startsWith('# Dados de acesso ao PostgreSQL do Legendas YT.'));
      expect(readEnv(novo), {'DB_HOST': 'h', 'DB_PASSWORD': ''});
    });
  });

  test('configFromForm: valida e mantém a senha salva quando vem em branco', () {
    final current = {'DB_PASSWORD': 'antiga'};
    final (ok, err) = configFromForm({
      'host': ' db.local ',
      'port': '',
      'dbname': 'legendas_yt',
      'user': 'ana',
      'password': '',
      'sslmode': '',
    }, current);
    expect(err, isEmpty);
    expect(ok, {
      'DB_HOST': 'db.local',
      'DB_PORT': '5432',
      'DB_NAME': 'legendas_yt',
      'DB_USER': 'ana',
      'DB_PASSWORD': 'antiga',
    });

    String error(Map<String, Object?> form) =>
        configFromForm({'host': 'h', 'port': '5432', 'dbname': 'd', 'user': 'u', 'sslmode': '', ...form}, current).$2;
    expect(error({'host': ''}), startsWith('Informe o servidor'));
    expect(error({'port': '70000'}), startsWith('A porta precisa'));
    expect(error({'port': 'abc'}), startsWith('A porta precisa'));
    expect(error({'dbname': ''}), startsWith('Informe o nome do banco'));
    expect(error({'user': ''}), startsWith('Informe o usuário'));
    expect(error({'sslmode': 'talvez'}), startsWith('Modo de conexão segura'));
    expect(error({'password': 'a\nb'}), startsWith('Os campos não podem'));
    expect(
      configFromForm({'host': 'h', 'dbname': 'd', 'user': 'u', 'sslmode': 'require'}, {}).$1['DB_SSLMODE'],
      'require',
    );
  });

  test('recentRows: id válido, sem repetidos, tipos certos', () {
    final now = DateTime.utc(2026, 11, 16, 12);
    final rows = recentRows([
      {
        'id': 'UF8uR6Z6KLc',
        'source': 'en',
        'at': 1763200000,
        'pos': 12.5,
        'dur': 904.2,
        'title': 'Steve',
        'author': '',
      },
      {'id': 'UF8uR6Z6KLc', 'source': 'pt'},
      {'id': 'curto'},
      {'id': 'jNQXAC9IVRw', 'source': 'xx', 'at': 'ontem', 'pos': double.nan, 'dur': -1},
    ], now: now);
    expect(rows, hasLength(2));
    expect(rows[0], {
      'id': 'UF8uR6Z6KLc',
      'source': 'en',
      'at': DateTime.fromMillisecondsSinceEpoch(1763200000 * 1000, isUtc: true),
      'pos': 12.5,
      'dur': 904.2,
      'title': 'Steve',
      'author': null,
    });
    expect(rows[1]['source'], 'auto');
    expect(rows[1]['at'], now);
    expect(rows[1]['pos'], isNull);
    expect(rows[1]['dur'], isNull);
  });

  test('mensagens de erro (as do banco.py)', () {
    final p = DbParams({'DB_HOST': 'localhost', 'DB_NAME': 'legendas_yt', 'DB_USER': 'ana'});
    String m(DbFailure f, {bool mobile = false, bool ios = false}) => friendlyDbError(f, p, mobile: mobile, ios: ios);
    expect(
      m(const DbFailure('password authentication failed', code: '28P01')),
      startsWith('O PostgreSQL recusou o usuário ou a senha'),
    );
    expect(
      m(const DbFailure('no pg_hba.conf entry for host "192.168.0.7"', code: '28000')),
      startsWith('O servidor PostgreSQL não aceita conexões deste aparelho'),
    );
    expect(
      m(const DbFailure('database "legendas_yt" does not exist', code: '3D000')),
      contains('CREATE DATABASE legendas_yt;'),
    );
    expect(
      m(const DbFailure('permission denied for schema public', code: '42501')),
      startsWith('O usuário ana não tem permissão'),
    );
    final offline = m(const DbFailure('Connection refused', network: true));
    expect(offline, startsWith('Sem conexão com o PostgreSQL em localhost:5432'));
    expect(offline, isNot(contains('celular')));
    expect(
      m(const DbFailure('Connection refused', network: true), mobile: true),
      contains('"localhost" é o próprio celular'),
    );
    expect(m(const DbFailure('x', sslUnsupported: true)), startsWith('O servidor não aceita conexão segura'));
    expect(
      m(const DbFailure('syntax error at or near "X"', code: '42601')),
      'Erro ao conectar ao banco de dados: syntax error at or near "X".$notSaving',
    );
    expect(DbParams({}).describe(), 'postgres@localhost:5432/legendas_yt');
  });

  group('Banco', () {
    late DateTime now;
    late FakeDb db;
    late int connects;
    Object? refuse; // o conector falha com isto

    Banco banco() => Banco(
      null,
      now: () => now,
      connect: () async {
        connects++;
        final r = refuse;
        if (r != null) throw r;
        db.open = true;
        return db;
      },
    );

    setUp(() {
      now = DateTime(2026, 11, 16, 10);
      db = FakeDb();
      connects = 0;
      refuse = null;
    });

    test('sem dados de acesso: não tenta nada', () async {
      final b = Banco({});
      expect(b.configured, isFalse);
      expect(await b.loadRecent(), isNull);
      expect(b.submit(() async {}), isFalse);
      expect((await b.check()).$2, notConfigured);
    });

    test('ao conectar cria as tabelas; numa falha espera 20 s para tentar de novo', () async {
      refuse = const DbFailure('Connection refused', network: true);
      final b = banco();
      final statuses = <String>[];
      b.onStatus = statuses.add;
      expect(await b.loadPrefs(), isNull);
      expect(b.error, startsWith('Sem conexão com o PostgreSQL'));
      expect(await b.loadPrefs(), isNull);
      expect(connects, 1, reason: 'antes de 20 s não tenta de novo');

      refuse = null;
      now = now.add(const Duration(seconds: 21));
      expect(await b.loadPrefs(), isEmpty);
      expect(connects, 2);
      expect(db.where('CREATE TABLE IF NOT EXISTS'), hasLength(8));
      expect(db.where('CREATE OR REPLACE VIEW frases_en_pt'), hasLength(1));
      expect(b.error, isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(statuses.last, isEmpty, reason: 'o aviso some quando volta');
    });

    test('wait: false não espera uma tentativa de conexão', () async {
      final b = banco();
      expect(await b.findTranscript('abcdefghijk', 'auto', wait: false), isNull);
      expect(connects, 0);
      await b.loadPrefs(); // conecta
      db.handler = (sql, _) => const [];
      expect(await b.findTranscript('abcdefghijk', 'auto', wait: false), isNull);
      expect(db.statements.last, startsWith('SELECT l.id, l.codigo'));
    });

    test('conexão perdida no meio: avisa e reconecta depois', () async {
      final b = banco();
      await b.loadPrefs();
      db.failNext = const DbFailure('connection closed', network: true);
      expect(await b.savePref('show', 'tr'), isFalse);
      expect(b.connected, isFalse);
      expect(b.error, startsWith('Sem conexão'));
      now = now.add(const Duration(seconds: 21));
      expect(await b.savePref('show', 'tr'), isTrue);
      expect(connects, 2);
    });

    test('erro num comando (não de conexão) não derruba a conexão', () async {
      final b = banco();
      await b.loadPrefs();
      db.failNext = const DbFailure('value too long for type character varying(40)', code: '22001');
      expect(await b.savePref('x' * 50, 1), isFalse);
      expect(b.error, 'Erro no banco de dados: value too long for type character varying(40)');
      expect(b.connected, isTrue);
    });

    test('fila de gravações: na ordem, sem esperar', () async {
      final b = banco();
      final order = <int>[];
      for (var i = 0; i < 3; i++) {
        b.submit(() async {
          await Future<void>.delayed(Duration(milliseconds: 5 * (3 - i)));
          order.add(i);
        });
      }
      expect(b.pending, 3);
      expect(await b.flush(), isTrue);
      expect(order, [0, 1, 2]);
      expect(b.pending, 0);
    });

    test('recentes: grava a lista inteira na ordem da tela e lê de volta', () async {
      final b = banco();
      expect(
        await b.saveRecent([
          {'id': 'aaaaaaaaaaa', 'source': 'auto', 'at': 1763200000, 'title': 'A', 'pos': 10.0, 'dur': 100.0},
          {'id': 'bbbbbbbbbbb', 'source': 'pt', 'at': 1763100000},
        ]),
        isTrue,
      );
      expect(db.statements, [
        startsWith(
          'INSERT INTO videos (id, url, titulo, autor) VALUES (\$1, \$2, \$3, \$4), (\$5, \$6, \$7, \$8) ON CONFLICT',
        ),
        'DELETE FROM recentes',
        startsWith('INSERT INTO recentes (video_id, ordem, escolha, aberto_em, parou_em, duracao) VALUES'),
      ]);
      expect(
        db.statements.first,
        contains('WHERE (EXCLUDED.titulo IS NOT NULL AND EXCLUDED.titulo IS DISTINCT FROM videos.titulo)'),
        reason: 'vídeo que já estava igual no banco não é regravado',
      );
      final recentes = db.where('INSERT INTO recentes').single.$2;
      expect(recentes.sublist(0, 6), [
        'aaaaaaaaaaa',
        0,
        'auto',
        DateTime.fromMillisecondsSinceEpoch(1763200000000, isUtc: true),
        10.0,
        100.0,
      ]);
      expect(recentes.sublist(6, 9), ['bbbbbbbbbbb', 1, 'pt']);

      db.handler = (sql, _) => sql.startsWith('SELECT r.video_id')
          ? [
              ['aaaaaaaaaaa', 'auto', DateTime.utc(2025, 11, 15, 10), 10.0, 100.0, 'A', null],
            ]
          : const [];
      expect(await b.loadRecent(), [
        {
          'id': 'aaaaaaaaaaa',
          'url': 'https://www.youtube.com/watch?v=aaaaaaaaaaa',
          'source': 'auto',
          'at': DateTime.utc(2025, 11, 15, 10).millisecondsSinceEpoch ~/ 1000,
          'title': 'A',
          'pos': 10.0,
          'dur': 100.0,
        },
      ]);
    });

    test('inserções em lotes de 500 linhas', () async {
      final b = banco();
      await b.saveRecent([
        for (var i = 0; i < 1201; i++) {'id': 'v${i.toString().padLeft(10, '0')}', 'at': 1763200000},
      ]);
      expect(db.where('INSERT INTO videos'), hasLength(3)); // 500 + 500 + 201
      expect(db.where('INSERT INTO videos').last.$2, hasLength(201 * 4));
      expect(db.where('INSERT INTO recentes'), hasLength(3));
    });

    test('só a posição e o título: atualiza as linhas, sem mexer na lista', () async {
      final b = banco();
      expect(await b.updateRecent([]), isTrue);
      expect(connects, 0, reason: 'nada para gravar');
      expect(
        await b.updateRecent([
          {'id': 'aaaaaaaaaaa', 'source': 'auto', 'at': 1763200000, 'title': 'A', 'pos': 42.0, 'dur': 600.0},
          {'id': 'bbbbbbbbbbb', 'pos': 5.0},
        ]),
        isTrue,
      );
      expect(db.statements, [
        startsWith('UPDATE recentes SET parou_em'),
        startsWith('UPDATE videos SET titulo'),
        startsWith('UPDATE recentes SET parou_em'),
      ]);
      expect(
        [for (final e in db.where('UPDATE')) e.$2],
        [
          [42.0, 600.0, 'aaaaaaaaaaa'],
          ['A', null, 'aaaaaaaaaaa'],
          [5.0, null, 'bbbbbbbbbbb'],
        ],
      );
    });

    test('a lista tem todos os vídeos do banco: os que faltam entram no fim, os mais novos primeiro', () async {
      final b = banco();
      db.handler = (sql, _) => sql.startsWith('INSERT INTO recentes')
          ? [
              ['xxxxxxxxxxx'],
              ['yyyyyyyyyyy'],
            ]
          : const [];
      expect(await b.addMissingVideos(), 2);
      final sql = db.statements.single;
      expect(sql, startsWith('INSERT INTO recentes (video_id, ordem, escolha, aberto_em) SELECT v.id, m.ultima + '));
      expect(sql, contains('ROW_NUMBER() OVER (ORDER BY v.criado_em DESC, v.id)'));
      expect(sql, contains('WHERE NOT EXISTS (SELECT 1 FROM recentes r WHERE r.video_id = v.id)'));
      expect(sql, endsWith('ON CONFLICT (video_id) DO NOTHING RETURNING video_id'));
    });
    test('preferências em JSON', () async {
      final b = banco();
      await b.savePref('subSize', 28);
      expect(db.where('INSERT INTO preferencias').single.$2, ['subSize', '28']);
      db.handler = (sql, _) => [
        ['show', '"tr"'],
        ['subSize', '28'],
        ['estragada', '{'],
      ];
      expect(await b.loadPrefs(), {'show': 'tr', 'subSize': 28});
    });

    SubtitleMeta meta() => const SubtitleMeta(
      cues: [Cue(1, 2, "Don't stop"), Cue(3, 2, 'stop now'), Cue(5, 1, '')],
      sourceName: 'English',
      sourceCode: 'en-US',
      generated: false,
      target: 'pt',
      targetName: 'Português',
    );

    /// Respostas de um banco que grava a legenda 42, frases 1000+ordem e palavras 500+.
    List<List<Object?>> tracker(String sql, List<Object?> params) {
      if (sql.startsWith('INSERT INTO legendas')) {
        return [
          [42],
        ];
      }
      if (sql.startsWith('SELECT COUNT(*) FROM frases')) {
        return [
          [0],
        ];
      }
      if (sql.startsWith('INSERT INTO frases (')) {
        return [
          for (var i = 0; i < params.length; i += 5) [1000 + (params[i + 1]! as int), params[i + 1]],
        ];
      }
      if (sql.startsWith('SELECT palavra, id FROM palavras')) {
        return [
          for (var i = 1; i < params.length; i++) [params[i], 500 + i],
        ];
      }
      if (sql.startsWith('SELECT ordem, id FROM frases')) {
        return [
          for (var i = 1; i < params.length; i++) [params[i], 1000 + (params[i]! as int)],
        ];
      }
      return const [];
    }

    test('legenda nova: faixa, falas e palavras de cada fala', () async {
      final b = banco();
      db.handler = tracker;
      final saved = SavedTrack(meta: meta());
      await b.saveTranscript(saved, 'abcdefghijk', 'auto');
      expect(saved.id, 42);
      expect(saved.db, b.generation);
      expect(db.where('INSERT INTO legendas (').single.$2, ['abcdefghijk', 'en-US', 'en', 'English', false, 'pt']);
      expect(db.where('INSERT INTO legendas_escolhidas').single.$2, ['abcdefghijk', 'auto', 42]);
      final frases = db.where('INSERT INTO frases (').single.$2;
      expect(frases, [42, 0, 1.0, 2.0, "Don't stop", 42, 1, 3.0, 2.0, 'stop now', 42, 2, 5.0, 1.0, '']);
      expect(db.where('INSERT INTO palavras').single.$2, ['en', "don't", 'en', 'now', 'en', 'stop']);
      // "stop" aparece nas duas falas; cada palavra na sua posição
      final links = db.where('INSERT INTO frases_palavras').single.$2;
      expect(links, [
        1000, false, 0, 501, 1000, false, 1, 503, //
        1001, false, 0, 503, 1001, false, 1, 502,
      ]);
    });

    test('traduções: atualiza as falas e grava as palavras da tradução', () async {
      final b = banco();
      db.handler = tracker;
      final saved = SavedTrack(meta: meta());
      await b.saveTranscript(saved, 'abcdefghijk', 'auto');
      db.log.clear();
      await b.saveTranslations(saved, [(0, 'Não pare'), (1, 'pare agora')]);
      expect(db.statements, [
        'UPDATE frases SET traducao = CASE ordem WHEN \$1 THEN \$2 WHEN \$3 THEN \$4 END '
            'WHERE legenda_id = \$5 AND ordem IN (\$6, \$7)',
        'SELECT ordem, id FROM frases WHERE legenda_id = \$1 AND ordem IN (\$2, \$3)',
        'DELETE FROM frases_palavras WHERE da_traducao = \$1 AND frase_id IN (\$2, \$3)',
        startsWith('INSERT INTO palavras'),
        startsWith('SELECT palavra, id FROM palavras'),
        startsWith('INSERT INTO frases_palavras'),
      ]);
      expect(db.log.first.$2, [0, 'Não pare', 1, 'pare agora', 42, 0, 1]);
      expect(db.where('INSERT INTO palavras').single.$2, ['pt', 'agora', 'pt', 'não', 'pt', 'pare']);

      // banco trocado: os ids da faixa não valem mais
      db.log.clear();
      await b.reconfigure({'DB_HOST': 'outro'});
      await b.saveTranslations(saved, [(0, 'x')]);
      expect(db.statements, isEmpty);
    });

    test('lê a faixa guardada, com as traduções já feitas', () async {
      final b = banco();
      db.handler = (sql, params) {
        if (sql.startsWith('SELECT l.id')) {
          return [
            [42, 'en', 'English', true, 'pt'],
          ];
        }
        if (sql.startsWith('SELECT inicio')) {
          return [
            [1.0, 2.0, 'hello', 'olá'],
            [3, 1, 'world', null],
          ];
        }
        return const [];
      };
      final saved = await b.findTranscript('abcdefghijk', 'auto');
      expect(saved!.id, 42);
      expect(saved.meta.cues.map((c) => c.text), ['hello', 'world']);
      expect(saved.meta.cues[1].start, 3.0);
      expect(saved.meta.generated, isTrue);
      expect(saved.meta.targetName, 'Português');
      expect(saved.translations, [(0, 'olá')]);
      final head = db.where('SELECT l.id').single;
      expect(head.$1, contains('JOIN legendas_escolhidas e ON e.legenda_id = l.id'));
      expect(head.$2, ['abcdefghijk', 'auto']);
    });

    test('check conta o que está guardado', () async {
      final b = banco();
      db.handler = (sql, _) => sql.startsWith('SELECT COUNT(*)')
          ? [
              [1234],
            ]
          : const [];
      final (ok, msg) = await b.check();
      expect(ok, isTrue);
      expect(msg, 'banco de teste, com 1.234 vídeos, 1.234 legendas, 1.234 falas e 1.234 palavras guardadas');
    });
  });
}
