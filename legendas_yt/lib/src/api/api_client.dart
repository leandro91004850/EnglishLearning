/// O cliente da API do Legendas YT (o servidor em Python, projeto api_english).
///
/// A lista de vídeos, as preferências, as legendas com a tradução e o diagnóstico vêm da API: o
/// app não fala com o banco de dados, com o Google Tradutor nem com as legendas do YouTube (só o
/// player do YouTube toca o vídeo, no próprio app).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/subtitles.dart';
import 'api_settings.dart';

const Duration requestTimeout = Duration(seconds: 20);
const Duration diagnoseTimeout = Duration(seconds: 120); // o diagnóstico testa os tradutores um por um

/// Falha ao falar com a API, com a mensagem para a tela.
class ApiFailure implements Exception {
  const ApiFailure(this.message, {this.status});

  final String message;

  /// Código HTTP da resposta; null se a API não respondeu.
  final int? status;

  @override
  String toString() => message;
}

/// A API está no ar, e a situação do banco de dados dela.
class ApiStatus {
  const ApiStatus({required this.version, required this.dbOk, required this.dbMessage});

  factory ApiStatus.fromJson(Map<String, dynamic> json) {
    final db = json['banco'] is Map ? json['banco'] as Map : const {};
    return ApiStatus(
      version: '${json['versao'] ?? ''}',
      dbOk: db['ok'] == true,
      dbMessage: '${db['mensagem'] ?? ''}',
    );
  }

  final String version;
  final bool dbOk;

  /// Problema com o banco; com status(check: true) e o banco no ar, o que está guardado nele.
  final String dbMessage;
}

/// A lista de vídeos (Recentes) no formato do historico.json, e o problema com o banco ("" = nenhum).
class VideoList {
  const VideoList(this.videos, this.dbMessage);

  factory VideoList.fromJson(Map<String, dynamic> json) => VideoList(
        [
          for (final v in json['videos'] as List? ?? const [])
            if (v is Map<String, dynamic>) v,
        ],
        '${json['banco'] ?? ''}',
      );

  final List<Map<String, dynamic>> videos;
  final String dbMessage;
}

/// O andamento da legenda de um vídeo na API.
class JobState {
  const JobState({
    required this.job,
    required this.video,
    required this.message,
    required this.error,
    required this.ready,
    required this.finished,
    required this.title,
    required this.author,
    required this.meta,
    required this.translations,
    required this.total,
  });

  factory JobState.fromJson(Map<String, dynamic> json) {
    final meta = json['meta'];
    return JobState(
      job: '${json['job'] ?? ''}',
      video: '${json['video'] ?? ''}',
      message: '${json['mensagem'] ?? ''}',
      error: json['erro'] == true,
      ready: json['pronto'] == true,
      finished: json['fim'] == true,
      title: '${json['titulo'] ?? ''}',
      author: '${json['autor'] ?? ''}',
      meta: meta is Map<String, dynamic> ? SubtitleMeta.fromJson(meta) : null,
      translations: [
        for (final p in json['traducoes'] as List? ?? const [])
          if (p is List && p.length == 2 && p[0] is int && p[1] is String) (p[0] as int, p[1] as String),
      ],
      total: json['total'] is int ? json['total'] as int : 0,
    );
  }

  final String job;
  final String video;
  final String message;
  final bool error;

  /// Tudo traduzido.
  final bool ready;

  /// A API terminou: pronta, com erro ou parada. Até lá, o app continua perguntando.
  final bool finished;
  final String title;
  final String author;

  /// As falas e os idiomas: só quando pedidos (cues: true) e já prontos.
  final SubtitleMeta? meta;

  /// As traduções novas (desde a quantidade pedida): (fala, tradução).
  final List<(int, String)> translations;

  /// Quantas traduções a API já tem (o "desde" da próxima pergunta).
  final int total;
}

/// Uma frase das lições: a frase em inglês para traduzir montando a tradução com as fichas, ou para repetir
/// em voz alta. Vem das legendas do banco, pela ordem das palavras que mais se repetem nelas.
class QuizItem {
  const QuizItem({
    this.id = 0,
    required this.position,
    required this.word,
    required this.times,
    required this.phrase,
    required this.translation,
    required this.answer,
    required this.tiles,
    required this.repeats,
    required this.videoId,
    required this.videoTitle,
    required this.start,
  });

  factory QuizItem.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? v) => [for (final x in v as List? ?? const []) '$x'];
    final video = json['video'] is Map ? json['video'] as Map : const {};
    num number(Object? v) => v is num ? v : 0;
    return QuizItem(
      id: number(json['id']).toInt(),
      position: number(json['posicao']).toInt(),
      word: '${json['palavra'] ?? ''}',
      times: number(json['vezes']).toInt(),
      phrase: '${json['frase'] ?? ''}',
      translation: '${json['traducao'] ?? ''}',
      answer: strings(json['resposta']),
      tiles: strings(json['fichas']),
      repeats: number(json['repeticoes']).toInt(),
      videoId: '${video['id'] ?? ''}',
      videoTitle: '${video['titulo'] ?? ''}',
      start: number(video['inicio']).toDouble(),
    );
  }

  /// O id da frase no banco (é por ele que ela é arquivada).
  final int id;

  /// Posição no quiz (de 1): a ordem das palavras, da que mais se repete.
  final int position;

  /// A palavra em inglês que esta frase ensina (fica destacada).
  final String word;

  /// Quantas vezes a palavra aparece nas legendas do banco.
  final int times;
  final String phrase;
  final String translation;

  /// As palavras da tradução, na ordem certa.
  final List<String> answer;

  /// As fichas para montar: as da resposta e algumas a mais, embaralhadas.
  final List<String> tiles;

  /// Quantas vezes esta frase aparece nas legendas.
  final int repeats;
  final String videoId;
  final String videoTitle;

  /// Onde a frase começa no vídeo (segundos).
  final double start;
}

class QuizBatch {
  const QuizBatch({
    required this.items,
    required this.total,
    required this.phrases,
    required this.words,
    required this.dbMessage,
    this.archived = 0,
  });

  factory QuizBatch.fromJson(Map<String, dynamic> json) => QuizBatch(
        items: [
          for (final i in json['itens'] as List? ?? const [])
            if (i is Map<String, dynamic>) QuizItem.fromJson(i),
        ],
        total: json['total'] is int ? json['total'] as int : 0,
        phrases: json['frases'] is int ? json['frases'] as int : 0,
        words: json['palavras'] is int ? json['palavras'] as int : 0,
        dbMessage: '${json['banco'] ?? ''}',
        archived: json['arquivadas'] is int ? json['arquivadas'] as int : 0,
      );

  /// Quantas frases estão arquivadas (fora das lições).
  final int archived;

  final List<QuizItem> items;

  /// Quantas frases o quiz tem ao todo.
  final int total;

  /// Quantas falas do banco foram analisadas, e quantas palavras diferentes elas têm.
  final int phrases;
  final int words;

  /// Problema com o banco ("" = nenhum).
  final String dbMessage;
}

/// Uma das palavras em inglês que mais se repetem nas legendas do banco.
class WordStat {
  const WordStat({required this.word, required this.times, required this.phrases, required this.item});

  factory WordStat.fromJson(Map<String, dynamic> json) => WordStat(
        word: '${json['palavra'] ?? ''}',
        times: json['vezes'] is int ? json['vezes'] as int : 0,
        phrases: json['frases'] is int ? json['frases'] as int : 0,
        item: json['item'] is int ? json['item'] as int : null,
      );

  final String word;
  final int times;

  /// Em quantas falas ela aparece.
  final int phrases;

  /// A posição da frase dela no quiz (de 0); null se nenhuma frase serviu.
  final int? item;
}

class WordStats {
  const WordStats({required this.words, required this.total, required this.phrases, required this.quizItems, required this.dbMessage});

  factory WordStats.fromJson(Map<String, dynamic> json) => WordStats(
        words: [
          for (final w in json['palavras'] as List? ?? const [])
            if (w is Map<String, dynamic>) WordStat.fromJson(w),
        ],
        total: json['total'] is int ? json['total'] as int : 0,
        phrases: json['frases'] is int ? json['frases'] as int : 0,
        quizItems: json['itens'] is int ? json['itens'] as int : 0,
        dbMessage: '${json['banco'] ?? ''}',
      );

  final List<WordStat> words;

  /// Quantas palavras diferentes as falas têm, quantas falas foram analisadas e quantas frases o quiz tem.
  final int total;
  final int phrases;
  final int quizItems;
  final String dbMessage;
}

/// Uma frase arquivada: ela não aparece mais nas lições.
class ArchivedPhrase {
  const ArchivedPhrase({
    required this.id,
    required this.phrase,
    required this.translation,
    required this.videoId,
    required this.videoTitle,
    required this.start,
    required this.archivedAt,
  });

  factory ArchivedPhrase.fromJson(Map<String, dynamic> json) {
    final video = json['video'] is Map ? json['video'] as Map : const {};
    return ArchivedPhrase(
      id: json['id'] is int ? json['id'] as int : 0,
      phrase: '${json['frase'] ?? ''}',
      translation: '${json['traducao'] ?? ''}',
      videoId: '${video['id'] ?? ''}',
      videoTitle: '${video['titulo'] ?? ''}',
      start: video['inicio'] is num ? (video['inicio'] as num).toDouble() : 0,
      archivedAt: DateTime.tryParse('${json['arquivada_em'] ?? ''}'),
    );
  }

  final int id;
  final String phrase;
  final String translation;
  final String videoId;
  final String videoTitle;
  final double start;
  final DateTime? archivedAt;
}

class ApiClient {
  ApiClient(this._http, this.settings, {this.mobile = false});

  final http.Client _http;
  ApiSettings settings;

  /// No celular, "localhost" é o próprio celular: a mensagem de "sem conexão" ganha uma dica.
  final bool mobile;

  static const String notConfigured =
      'Servidor não configurado: preencha o endereço da API do Legendas YT em ⋮ › Servidor.';

  // ---- rotas ----

  Future<ApiStatus> status({bool check = false}) async =>
      ApiStatus.fromJson(await _call('GET', '/status', query: check ? const {'verificar': 'true'} : null));

  Future<VideoList> recent() async => VideoList.fromJson(await _call('GET', '/recentes'));

  Future<VideoList> reorder(List<String> ids) async =>
      VideoList.fromJson(await _call('PUT', '/recentes', body: {'ids': ids}));

  Future<bool> position(String videoId, double pos, double dur) async =>
      (await _call('POST', '/recentes/$videoId/posicao', body: {'pos': pos, 'dur': dur}))['ok'] == true;

  Future<Map<String, dynamic>> prefs() => _call('GET', '/preferencias');

  Future<Map<String, dynamic>> savePrefs(Map<String, Object> values) => _call('PUT', '/preferencias', body: values);

  /// Abre o vídeo na API; devolve o id da legenda, para acompanhar em [job].
  Future<String> open(String url, {String source = 'auto', bool keepPlace = false, bool restoring = false}) async {
    final r = await _call('POST', '/abrir', body: {
      'url': url,
      'escolha': source,
      'manter_lugar': keepPlace,
      'restaurando': restoring,
    });
    return '${r['job']}';
  }

  /// Andamento da legenda: [since] traduções o app já tem; [cues]: manda também as falas.
  Future<JobState> job(String id, {int since = 0, bool cues = false}) async => JobState.fromJson(
        await _call('GET', '/legendas/$id', query: {'desde': '$since', if (cues) 'falas': 'true'}),
      );

  Future<void> focus(String id, int index) => _call('POST', '/legendas/$id/foco', body: {'indice': index});

  /// Frases do quiz a partir da posição [start] (de 0).
  Future<QuizBatch> quiz({int start = 0, int count = 10}) async => QuizBatch.fromJson(
        await _call('GET', '/quiz', query: {'inicio': '$start', 'quantidade': '$count'}, timeout: diagnoseTimeout),
      );

  /// As palavras em inglês que mais se repetem nas legendas do banco.
  Future<WordStats> words({int count = 100}) async =>
      WordStats.fromJson(await _call('GET', '/palavras', query: {'quantidade': '$count'}, timeout: diagnoseTimeout));

  /// Arquiva a frase [id]: ela não aparece mais nas lições.
  Future<void> archive(int id) => _call('POST', '/frases/$id/arquivar');

  /// A frase arquivada [id] volta para as lições.
  Future<void> restore(int id) => _call('DELETE', '/frases/$id/arquivar');

  /// As frases arquivadas, as mais recentes primeiro.
  Future<List<ArchivedPhrase>> archived() async {
    final r = await _call('GET', '/frases/arquivadas');
    final message = '${r['banco'] ?? ''}';
    if (message.isNotEmpty) throw ApiFailure(message);
    return [
      for (final f in r['frases'] as List? ?? const [])
        if (f is Map<String, dynamic>) ArchivedPhrase.fromJson(f),
    ];
  }

  /// Testes no servidor: banco, tradutores e (com [url]) as legendas do YouTube.
  Future<(bool, List<String>)> diagnose(String? url) async {
    final r = await _call('GET', '/diagnostico', query: url == null ? null : {'url': url}, timeout: diagnoseTimeout);
    return (r['ok'] == true, [for (final line in r['linhas'] as List? ?? const []) '$line']);
  }

  // ---- HTTP ----

  Future<Map<String, dynamic>> _call(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Duration timeout = requestTimeout,
  }) async {
    if (!settings.configured) throw const ApiFailure(notConfigured);
    final base = Uri.parse('${settings.url}$path');
    final request = http.Request(method, query == null ? base : base.replace(queryParameters: query));
    request.headers['Accept'] = 'application/json';
    if (settings.token.isNotEmpty) request.headers['Authorization'] = 'Bearer ${settings.token}';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await _http.send(request).then(http.Response.fromStream).timeout(timeout);
    } on TimeoutException {
      throw ApiFailure('A API em ${settings.url} não respondeu a tempo. Confira o servidor e tente de novo.');
    } on SocketException catch (e) {
      throw ApiFailure(_offline(e.osError?.errorCode));
    } on HandshakeException {
      throw ApiFailure('Falha na conexão segura (HTTPS) com a API em ${settings.url}: confira o endereço.');
    } on http.ClientException {
      throw ApiFailure(_offline(null));
    }

    Object? data;
    try {
      final text = utf8.decode(response.bodyBytes, allowMalformed: true);
      data = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      data = null;
    }
    final code = response.statusCode;
    if (code == 401) {
      throw const ApiFailure('A API recusou a chave de acesso: confira a chave em ⋮ › Servidor.', status: 401);
    }
    if (code >= 400) {
      final detail = data is Map && data['detail'] is String ? data['detail'] as String : '';
      throw ApiFailure(detail.isNotEmpty ? detail : 'Erro na API (HTTP $code).', status: code);
    }
    if (data is! Map<String, dynamic>) {
      throw ApiFailure(
        'Resposta inesperada de ${settings.url}: é mesmo o endereço da API do Legendas YT?',
        status: code,
      );
    }
    return data;
  }

  String _offline(int? errno) {
    final host = Uri.tryParse(settings.url)?.host ?? '';
    final local = host == 'localhost' || host == '127.0.0.1' || host == '::1';
    var hint = '';
    if (mobile && local) {
      hint = ' No celular, "localhost" é o próprio celular: use o endereço (IP) do computador onde a API roda.';
    } else if (mobile && errno == 65) {
      // EHOSTUNREACH no iPhone: em geral, a permissão de Rede Local foi negada
      hint = ' Se o servidor está na rede de casa, permita o acesso em Ajustes › Privacidade e Segurança › '
          'Rede Local › Legendas YT.';
    }
    return 'Sem conexão com a API em ${settings.url}: ela está ligada? Confira o endereço em ⋮ › Servidor.$hint';
  }
}
