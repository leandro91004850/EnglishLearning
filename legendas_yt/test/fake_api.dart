import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:legendas_yt/src/api/api_client.dart';
import 'package:legendas_yt/src/api/api_settings.dart';
import 'package:legendas_yt/src/youtube/video_id.dart';

const String apiUrl = 'http://api.test';

/// A API do Legendas YT de mentira, na memória, atrás de um MockClient: os testes usam o
/// ApiClient de verdade. down = true: a API não responde.
class FakeApi {
  bool down = false;
  List<Map<String, Object?>> videos = [];
  String dbMessage = '';
  Map<String, Object?> prefs = {};

  final List<http.Request> requests = [];
  final List<Map<String, dynamic>> opened = [];
  final List<List<String>> orders = [];
  final List<(String, double, double)> positions = [];
  final List<int> focuses = [];

  /// As frases do quiz (GET /quiz) e as palavras mais usadas (GET /palavras).
  List<Map<String, Object?>> quizItems = [];
  List<Map<String, Object?>> wordStats = [];

  /// Respostas de GET /legendas/{job}, uma por pergunta (a última se repete).
  List<Map<String, Object?>> jobStates = [jobState(finished: true, ready: true, message: 'pronto')];
  int _poll = 0;

  late final MockClient client = MockClient(handle);

  ApiClient api({String token = ''}) => ApiClient(client, ApiSettings(url: apiUrl, token: token));

  List<String> get paths => [for (final r in requests) '${r.method} ${r.url.path}'];

  Future<http.Response> handle(http.Request r) async {
    requests.add(r);
    if (down) throw const SocketException('Connection refused');
    final path = r.url.path;
    final body = r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>;
    http.Response json(Object data, [int status = 200]) =>
        http.Response.bytes(utf8.encode(jsonEncode(data)), status, headers: {'content-type': 'application/json'});

    switch ((r.method, path)) {
      case ('GET', '/status'):
        return json({
          'ok': true,
          'versao': '1.0.0',
          'banco': {'ok': dbMessage.isEmpty, 'mensagem': dbMessage.isEmpty ? 'banco de teste, com 0 vídeos' : dbMessage},
        });
      case ('GET', '/recentes'):
        return json({'videos': videos, 'banco': dbMessage});
      case ('PUT', '/recentes'):
        final ids = [for (final id in body['ids'] as List) '$id'];
        orders.add(ids);
        videos.sort((a, b) => ids.indexOf('${a['id']}').compareTo(ids.indexOf('${b['id']}')));
        return json({'videos': videos, 'banco': dbMessage});
      case ('GET', '/preferencias'):
        return json(prefs);
      case ('PUT', '/preferencias'):
        prefs.addAll(body);
        return json(prefs);
      case ('POST', '/abrir'):
        opened.add(body);
        final vid = extractVideoId('${body['url']}');
        if (vid == null) return json({'detail': 'Link do YouTube inválido.'}, 400);
        _poll = 0;
        return json({'job': 'job${opened.length}', 'video': vid});
      case ('GET', '/quiz'):
        final start = int.parse(r.url.queryParameters['inicio'] ?? '0');
        final count = int.parse(r.url.queryParameters['quantidade'] ?? '10');
        return json({
          'itens': quizItems.skip(start).take(count).toList(),
          'total': quizItems.length,
          'frases': 100,
          'palavras': 50,
          'banco': dbMessage,
        });
      case ('GET', '/palavras'):
        return json({'palavras': wordStats, 'total': 50, 'frases': 100, 'itens': quizItems.length, 'banco': dbMessage});
      case ('GET', '/diagnostico'):
        return json({
          'ok': true,
          'linhas': ['[OK]    Banco de dados: banco de teste', '[OK]    Google, 0.3 s: [...]'],
        });
    }
    if (r.method == 'POST' && path.startsWith('/recentes/') && path.endsWith('/posicao')) {
      positions.add((path.split('/')[2], (body['pos'] as num).toDouble(), (body['dur'] as num).toDouble()));
      return json({'ok': true});
    }
    if (r.method == 'POST' && path.startsWith('/legendas/') && path.endsWith('/foco')) {
      focuses.add(body['indice'] as int);
      return json({'ok': true});
    }
    if (r.method == 'GET' && path.startsWith('/legendas/')) {
      if (jobStates.isEmpty) return json({'detail': 'Legenda não encontrada: abra o vídeo de novo.'}, 404);
      return json(jobStates[math.min(_poll++, jobStates.length - 1)]);
    }
    return json({'detail': 'Not Found'}, 404);
  }
}

Map<String, Object?> video(String id, {int at = 1763200000, String title = '', double pos = 0, double dur = 0}) => {
      'id': id,
      'url': watchUrlFor(id),
      'source': 'auto',
      'at': at,
      if (title.isNotEmpty) 'title': title,
      if (pos > 0) 'pos': pos,
      if (dur > 0) 'dur': dur,
    };

const Map<String, Object?> meta = {
  'cues': [
    {'start': 0, 'dur': 1.5, 'text': 'Hello'},
    {'start': 1.5, 'dur': 1, 'text': 'world'},
    {'start': 2.5, 'dur': 1, 'text': ''},
  ],
  'sourceName': 'English',
  'sourceCode': 'en',
  'generated': false,
  'target': 'pt',
  'targetName': 'Português',
};

Map<String, Object?> jobState({
  String message = '',
  bool error = false,
  bool ready = false,
  bool finished = false,
  Map<String, Object?>? withMeta,
  List<List<Object>> translations = const [],
  int total = 0,
  String title = '',
  String author = '',
}) =>
    {
      'job': 'job1',
      'video': 'aaaaaaaaaaa',
      'escolha': 'auto',
      'mensagem': message,
      'erro': error,
      'pronto': ready,
      'fim': finished,
      'titulo': title,
      'autor': author,
      'meta': withMeta,
      'traducoes': translations,
      'total': total,
    };

/// Uma frase do quiz como a API manda.
Map<String, Object?> quizItem(int position, String word, String phrase, String translation, List<String> answer,
        List<String> tiles) =>
    {
      'posicao': position,
      'palavra': word,
      'vezes': 100 - position,
      'frase': phrase,
      'traducao': translation,
      'resposta': answer,
      'fichas': tiles,
      'repeticoes': 2,
      'video': {'id': 'aaaaaaaaaaa', 'titulo': 'Vídeo A', 'inicio': 12.5, 'duracao': 2.0},
    };

final List<Map<String, Object?>> sampleQuiz = [
  quizItem(1, 'you', 'I love you', 'Eu te amo', ['Eu', 'te', 'amo'], ['amo', 'Eu', 'pai', 'te', 'meu']),
  quizItem(2, 'dad', 'my dad', 'meu pai', ['meu', 'pai'], ['pai', 'Esse', 'meu', 'mãe']),
  quizItem(3, 'my', 'my dog', 'meu cachorro', ['meu', 'cachorro'], ['cachorro', 'meu', 'gato']),
];
