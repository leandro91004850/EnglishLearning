import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:legendas_yt/src/api/api_client.dart';
import 'package:legendas_yt/src/api/api_settings.dart';

import 'fake_api.dart';

void main() {
  Future<String> failure(Future<Object?> Function() call) async {
    try {
      await call();
    } on ApiFailure catch (e) {
      return e.message;
    }
    fail('devia falhar');
  }

  ApiClient answering(http.Response response, {String url = apiUrl, bool mobile = false}) =>
      ApiClient(MockClient((_) async => response), ApiSettings(url: url), mobile: mobile);

  /// Resposta como a da API (FastAPI): JSON em UTF-8.
  http.Response json(String body, int status) =>
      http.Response.bytes(utf8.encode(body), status, headers: {'content-type': 'application/json'});

  group('ApiClient', () {
    test('manda a chave de acesso e lê a lista', () async {
      final fake = FakeApi()..videos = [video('aaaaaaaaaaa', title: 'A')];
      final list = await fake.api(token: 'segredo').recent();
      expect(list.videos.single['title'], 'A');
      expect(list.dbMessage, isEmpty);
      expect(fake.requests.single.headers['Authorization'], 'Bearer segredo');
      await fake.api().recent();
      expect(fake.requests.last.headers.containsKey('Authorization'), isFalse, reason: 'sem chave, sem cabeçalho');
    });

    test('sem endereço: não tenta', () async {
      final api = ApiClient(MockClient((_) async => fail('não devia chamar')), const ApiSettings());
      expect(await failure(api.recent), ApiClient.notConfigured);
    });

    test('mensagens de erro', () async {
      final fake = FakeApi()..down = true;
      expect(await failure(fake.api().recent),
          'Sem conexão com a API em http://api.test: ela está ligada? Confira o endereço em ⋮ › Servidor.');

      final local = ApiClient(fake.client, const ApiSettings(url: 'http://localhost:8000'), mobile: true);
      expect(await failure(local.recent), contains('No celular, "localhost" é o próprio celular'));

      expect(await failure(answering(json('{"detail": "x"}', 401)).recent),
          'A API recusou a chave de acesso: confira a chave em ⋮ › Servidor.');
      expect(await failure(answering(json('{"detail": "Link do YouTube inválido."}', 400)).recent),
          'Link do YouTube inválido.');
      expect(await failure(answering(http.Response('', 502)).recent), 'Erro na API (HTTP 502).');
      expect(await failure(answering(http.Response('<html>roteador</html>', 200)).recent),
          'Resposta inesperada de http://api.test: é mesmo o endereço da API do Legendas YT?');
    });

    test('andamento da legenda: falas, traduções e título', () async {
      final fake = FakeApi()
        ..jobStates = [
          jobState(
            message: 'Traduzindo para Português… 50%',
            withMeta: meta,
            translations: [
              [0, 'Olá'],
            ],
            total: 1,
            title: 'Meu vídeo',
          ),
        ];
      final state = await fake.api().job('job1', cues: true);
      expect(state.meta!.cues.map((c) => c.text), ['Hello', 'world', '']);
      expect(state.meta!.targetName, 'Português');
      expect(state.translations, [(0, 'Olá')]);
      expect(state.total, 1);
      expect(state.title, 'Meu vídeo');
      expect(state.finished, isFalse);
      expect(fake.requests.single.url.queryParameters, {'desde': '0', 'falas': 'true'});
    });

    test('abrir manda o vídeo, a escolha e se fica no lugar', () async {
      final fake = FakeApi();
      expect(await fake.api().open('https://youtu.be/aaaaaaaaaaa', source: 'pt', keepPlace: true), 'job1');
      expect(fake.opened.single,
          {'url': 'https://youtu.be/aaaaaaaaaaa', 'escolha': 'pt', 'manter_lugar': true, 'restaurando': false});
      expect(jsonDecode(fake.requests.single.body), fake.opened.single);
    });
  });

  group('ApiSettings', () {
    test('endereço da tela', () {
      const current = ApiSettings(url: 'http://velho:8000', token: 'antiga');
      var (s, error) = ApiSettings.fromForm(' 192.168.0.10:8000/ ', '', current);
      expect(error, isEmpty);
      expect(s.url, 'http://192.168.0.10:8000');
      expect(s.token, 'antiga', reason: 'chave em branco mantém a salva');
      (s, error) = ApiSettings.fromForm('https://api.exemplo.com/legendas/', 'nova', current);
      expect((s.url, s.token), ('https://api.exemplo.com/legendas', 'nova'));
      expect(ApiSettings.fromForm('', '', current).$2, startsWith('Informe o endereço'));
      expect(ApiSettings.fromForm('ftp://x', '', current).$2, startsWith('Endereço inválido'));
      expect(ApiSettings.fromForm('http://x', 'a b', current).$2, startsWith('A chave de acesso não pode'));
    });

    test('grava e lê no aparelho', () {
      final dir = Directory.systemTemp.createTempSync('legendas_api');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/servidor.json');
      expect(ApiSettings.read(file).configured, isFalse);
      expect(const ApiSettings(url: 'http://x:8000', token: 'k').write(file), isTrue);
      final read = ApiSettings.read(file);
      expect((read.url, read.token), ('http://x:8000', 'k'));
    });
  });
}
