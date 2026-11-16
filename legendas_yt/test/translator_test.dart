import 'dart:convert';
import 'dart:io' show HttpDate;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:legendas_yt/src/translation/translator.dart';

/// Relógio de mentira: `sleep` só avança o relógio.
class FakeClock {
  DateTime now = DateTime(2026, 11, 15, 10);
  final List<Duration> sleeps = [];

  Future<void> sleep(Duration d) async {
    sleeps.add(d);
    now = now.add(d);
  }
}

typedef Handler = http.Response Function(http.Request request);

http.Response json(Object data, {int status = 200, Map<String, String> headers = const {}}) =>
    http.Response.bytes(utf8.encode(jsonEncode(data)), status,
        headers: {'content-type': 'application/json; charset=utf-8', ...headers});

/// Resposta do translate_a/single: um trecho por linha, como o Google manda.
http.Response googleSingle(String translated) {
  final parts = translated.split('\n');
  return json([
    [
      for (var i = 0; i < parts.length; i++)
        [i < parts.length - 1 ? '${parts[i]}\n' : parts[i], 'src', null, null, 10],
    ],
    null,
    'en',
  ]);
}

void main() {
  late FakeClock fake;
  late List<http.Request> requests;

  TranslationService service(Handler handler) {
    return TranslationService(
      client: MockClient((req) async {
        requests.add(req);
        return handler(req);
      }),
      now: () => fake.now,
      sleep: fake.sleep,
    );
  }

  setUp(() {
    fake = FakeClock();
    requests = [];
  });

  group('Google', () {
    test('modo 1: uma fala por linha', () async {
      final s = service((req) => googleSingle('Olá\nTudo bem?'));
      final t = Translator(s, 'en', 'pt');
      expect(await t.translate(['Hello', 'How are you?']), ['Olá', 'Tudo bem?']);
      expect(t.last, 'Google');
      expect(requests.single.url.queryParameters, containsPair('q', 'Hello\nHow are you?'));
      expect(requests.single.headers['User-Agent'], contains('Chrome/'));
    });

    test('modo 1 desalinhou: vai para o modo 2 (itens)', () async {
      final s = service((req) => req.url.path == '/translate_a/single'
          ? googleSingle('Olá, tudo bem?')
          : json(['Olá', 'Tudo bem?']));
      final t = Translator(s, 'en', 'pt');
      expect(await t.translate(['Hello', 'How are you?']), ['Olá', 'Tudo bem?']);
      expect(requests.map((r) => r.url.path), ['/translate_a/single', '/translate_a/t']);
      expect(requests[1].body, 'q=Hello&q=How+are+you%3F');
    });

    test('modo 2 com origem "auto" devolve [tradução, idioma]', () async {
      final s = service((req) => json([
            ['Olá', 'en'],
            ['Tudo bem?', 'en'],
          ]));
      expect(await s.googleItems(['Hello', 'How are you?'], 'auto', 'pt'), ['Olá', 'Tudo bem?']);
    });

    test('os dois desalinharam: fala por fala', () async {
      final s = service((req) {
        if (req.url.path == '/translate_a/t') return json(['só um']);
        final q = req.url.queryParameters['q']!;
        return q.contains('\n') ? googleSingle('tudo junto') : googleSingle('[$q]');
      });
      final t = Translator(s, 'en', 'pt');
      expect(await t.translate(['a', 'b', 'c']), ['[a]', '[b]', '[c]']);
      expect(requests.where((r) => r.url.queryParameters['q']?.contains('\n') == false), hasLength(3));
    });

    test('HTTP 429 com Retry-After: bloqueia e espaça os pedidos depois', () async {
      var blocked = true;
      final s = service((req) => blocked
          ? http.Response('', 429, headers: {'retry-after': '30'})
          : googleSingle('ok'));
      final err = await s.googleBatch(['x'], 'en', 'pt').then<Object?>((_) => null, onError: (Object e) => e);
      expect(err, isA<RateLimited>());
      expect((err! as RateLimited).until, fake.now.add(const Duration(seconds: 30)));

      // durante o bloqueio nenhum pedido sai
      final before = requests.length;
      await expectLater(s.googleBatch(['x'], 'en', 'pt'), throwsA(isA<RateLimited>()));
      expect(requests.length, before);

      // passou o bloqueio: os pedidos saem no máximo 1 a cada 2 s
      fake.now = fake.now.add(const Duration(seconds: 31));
      blocked = false;
      await s.googleBatch(['x'], 'en', 'pt');
      await s.googleBatch(['x'], 'en', 'pt');
      expect(fake.sleeps, [const Duration(seconds: 2)]);
    });

    test('429 sem Retry-After: 2, 5, 10 e 15 min; uma resposta boa zera a conta', () async {
      var status = 429;
      final s = service((req) => status == 429 ? http.Response('', 429) : googleSingle('ok'));
      // (o relógio só anda nas esperas; fake.now logo depois do pedido é a hora dele)
      final waits = <Duration>[];
      for (var i = 0; i < 5; i++) {
        try {
          await s.googleBatch(['x'], 'en', 'pt');
        } on RateLimited catch (e) {
          waits.add(e.until.difference(fake.now));
          fake.now = e.until;
        }
      }
      expect(waits.map((d) => d.inSeconds), [120, 300, 600, 900, 900]);

      status = 200;
      await s.googleBatch(['x'], 'en', 'pt');
      status = 429;
      final again = await s.googleBatch(['x'], 'en', 'pt').then<Object?>((_) => null, onError: (Object e) => e);
      expect((again! as RateLimited).until.difference(fake.now).inSeconds, 120);
    });

    test('sem conexão: não tenta o outro modo do Google', () async {
      final s = TranslationService(client: MockClient((req) async {
        requests.add(req);
        throw http.ClientException('offline');
      }), now: () => fake.now, sleep: fake.sleep);
      final t = Translator(s, 'en', 'pt', sourceLang: 'auto');
      await expectLater(t.translate(['x']), throwsA(isA<TranslateError>()));
      expect(requests.where((r) => r.url.host == googleHost), hasLength(1));
    });
  });

  group('MyMemory (reserva)', () {
    http.Response myMemory(String text, {int status = 200, Object? details, bool? quotaFinished}) => json({
          'responseData': {'translatedText': text, 'match': 1},
          'responseStatus': status,
          'responseDetails': ?details,
          'quotaFinished': ?quotaFinished,
        });

    test('o Google bloqueou: a reserva traduz e o app sabe por quê', () async {
      final s = service((req) => req.url.host == googleHost
          ? http.Response('', 429)
          : myMemory('Ol&aacute;\nTudo bem?'));
      final t = Translator(s, 'en', 'pt', sourceLang: 'en-US');
      expect(await t.translate(['Hello', 'How are you?']), ['Olá', 'Tudo bem?']);
      expect(t.last, 'MyMemory');
      expect(t.googleBlocked, isTrue);
      expect(t.used, {'MyMemory'});
      final mm = requests.last.url.queryParameters;
      expect(mm['langpair'], 'en|pt-BR');
      expect(mm['q'], 'Hello\nHow are you?');
    });

    test('a reserva também falhou: RateLimited com o motivo da reserva', () async {
      final s = service((req) => req.url.host == googleHost
          ? http.Response('', 429)
          : myMemory('MYMEMORY WARNING: YOU USED ALL AVAILABLE FREE TRANSLATIONS FOR TODAY. '
              'NEXT AVAILABLE IN 10 HOURS 20 MINUTES 33 SECONDS', status: 429));
      final t = Translator(s, 'en', 'pt', sourceLang: 'en');
      final err = await t.translate(['Hello']).then<Object?>((_) => null, onError: (Object e) => e);
      expect(err, isA<RateLimited>());
      expect((err! as RateLimited).fallback, startsWith('MyMemory (reserva): a cota grátis do dia acabou'));

      // a cota fica marcada até a hora que o MyMemory disse
      final before = requests.where((r) => r.url.host == myMemoryHost).length;
      await expectLater(s.myMemoryBatch(['x'], 'en', 'pt'), throwsA(isA<QuotaExceeded>()));
      expect(requests.where((r) => r.url.host == myMemoryHost).length, before);
      expect(
        (await s.myMemoryBatch(['x'], 'en', 'pt').then<Object?>((_) => null, onError: (Object e) => e)
                as QuotaExceeded)
            .until,
        fake.now.add(const Duration(hours: 10, minutes: 20, seconds: 33)),
      );
    });

    test('contagem de linhas errada: divide o lote ao meio', () async {
      final s = service((req) {
        final q = req.url.queryParameters['q']!;
        return myMemory(q.contains('\n') ? 'tudo numa linha' : q.toUpperCase());
      });
      expect(await s.myMemoryBatch(['a', 'b', 'c'], 'en', 'pt'), ['A', 'B', 'C']);
    });

    test('lotes de até 500 bytes e 1 pedido por segundo', () async {
      final s = service((req) {
        final q = req.url.queryParameters['q']!;
        return myMemory(q);
      });
      final lines = List.generate(5, (i) => 'ç' * 120); // 240 bytes cada
      await s.myMemoryBatch(lines, 'en', 'pt');
      expect(requests.map((r) => utf8.encode(r.url.queryParameters['q']!).length), [481, 481, 240]);
      expect(fake.sleeps, [const Duration(seconds: 1), const Duration(seconds: 1)]);
    });

    test('sem o idioma de origem não dá', () async {
      final s = service((req) => myMemory('x'));
      await expectLater(
        s.myMemoryBatch(['x'], 'auto', 'pt'),
        throwsA(isA<TranslateError>().having((e) => e.message, 'message', contains('idioma de origem'))),
      );
    });
  });

  test('myMemoryLang', () {
    expect(myMemoryLang('en-US'), 'en');
    expect(myMemoryLang('pt'), 'pt-BR');
    expect(myMemoryLang('pt-PT'), 'pt-BR');
    expect(myMemoryLang('zh-Hans'), 'zh-CN');
    expect(myMemoryLang('iw'), 'he');
    expect(myMemoryLang('es-419'), 'es');
    expect(myMemoryLang('auto'), isNull);
    expect(myMemoryLang(''), isNull);
  });

  test('byteGroups', () {
    expect(byteGroups(['aa', 'bb', 'cc'], 5), [
      ['aa', 'bb'],
      ['cc'],
    ]);
    expect(byteGroups(['muito comprido'], 5), [
      ['muito comprido'],
    ]);
  });

  test('parseRetryAfter', () {
    final now = DateTime.utc(2026, 11, 15, 12);
    expect(parseRetryAfter('120', now), 120);
    expect(parseRetryAfter(HttpDate.format(now.add(const Duration(minutes: 3))), now), 180);
    expect(parseRetryAfter('NaN', now), isNull);
    expect(parseRetryAfter('depois', now), isNull);
    expect(parseRetryAfter(null, now), isNull);
  });

  test('clock', () {
    final now = DateTime(2026, 11, 15, 10);
    expect(clock(DateTime(2026, 11, 15, 15, 30), now: now), 'às 15:30');
    expect(clock(DateTime(2026, 11, 16, 9, 12), now: now), 'amanhã às 09:12');
    expect(clock(DateTime(2026, 11, 18, 9, 12), now: now), 'em 18/11 às 09:12');
  });
}
