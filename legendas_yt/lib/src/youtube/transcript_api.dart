/// Legendas do YouTube, do mesmo jeito que o pacote Python
/// youtube-transcript-api 1.2 (MIT, Jonas Depoix), que o app.py usa:
///
///  1. abre a página do vídeo para pegar a chave da API interna (InnerTube),
///     aceitando o aviso de cookies se ele aparecer;
///  2. pede a lista de faixas de legenda como o app de Android do YouTube;
///  3. baixa a faixa escolhida em XML e tira as tags.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/cue.dart';
import '../core/text.dart';

const String watchUrl = 'https://www.youtube.com/watch?v=';
const String innertubeApiUrl = 'https://www.youtube.com/youtubei/v1/player?key=';
const Map<String, Object> innertubeContext = {
  'client': {'clientName': 'ANDROID', 'clientVersion': '20.10.38'},
};
const Duration requestTimeout = Duration(seconds: 30);

// Motivos de falha (playabilityStatus.reason), iguais aos do pacote Python.
// O apóstrofo do primeiro é o tipográfico (U+2019), como o YouTube manda.
const String _botDetected = 'Sign in to confirm you’re not a bot';
const String _ageRestricted = 'This video may be inappropriate for some users.';
const String _videoUnavailable = 'This video is unavailable';
const String _consentForm = 'action="https://consent.youtube.com/s"';

/// Erros ao buscar legendas, com os mesmos nomes do pacote Python
/// (o app.py mostra o nome quando não tem uma mensagem própria).
sealed class TranscriptError implements Exception {
  const TranscriptError(this.videoId);
  final String videoId;
  String get name;
  @override
  String toString() => '$name($videoId)';
}

final class TranscriptsDisabled extends TranscriptError {
  const TranscriptsDisabled(super.videoId);
  @override
  String get name => 'TranscriptsDisabled';
}

final class NoTranscriptFound extends TranscriptError {
  const NoTranscriptFound(super.videoId);
  @override
  String get name => 'NoTranscriptFound';
}

final class VideoUnavailable extends TranscriptError {
  const VideoUnavailable(super.videoId);
  @override
  String get name => 'VideoUnavailable';
}

final class InvalidVideoId extends TranscriptError {
  const InvalidVideoId(super.videoId);
  @override
  String get name => 'InvalidVideoId';
}

final class AgeRestricted extends TranscriptError {
  const AgeRestricted(super.videoId);
  @override
  String get name => 'AgeRestricted';
}

/// O YouTube desconfiou que é um robô ("Sign in to confirm you're not a bot").
class RequestBlocked extends TranscriptError {
  const RequestBlocked(super.videoId);
  @override
  String get name => 'RequestBlocked';
}

/// HTTP 429 ou página com captcha.
final class IpBlocked extends RequestBlocked {
  const IpBlocked(super.videoId);
  @override
  String get name => 'IpBlocked';
}

final class VideoUnplayable extends TranscriptError {
  const VideoUnplayable(super.videoId, this.reason, this.subreasons);
  final String? reason;
  final List<String> subreasons;
  @override
  String get name => 'VideoUnplayable';
}

/// A faixa só abre com um "proof of origin token", que este app não tem.
final class PoTokenRequired extends TranscriptError {
  const PoTokenRequired(super.videoId);
  @override
  String get name => 'PoTokenRequired';
}

final class YouTubeDataUnparsable extends TranscriptError {
  const YouTubeDataUnparsable(super.videoId);
  @override
  String get name => 'YouTubeDataUnparsable';
}

final class FailedToCreateConsentCookie extends TranscriptError {
  const FailedToCreateConsentCookie(super.videoId);
  @override
  String get name => 'FailedToCreateConsentCookie';
}

final class YouTubeRequestFailed extends TranscriptError {
  const YouTubeRequestFailed(super.videoId, this.statusCode);
  final int statusCode;
  @override
  String get name => 'YouTubeRequestFailed';
  @override
  String toString() => '$name($videoId, HTTP $statusCode)';
}

/// Sem resposta do YouTube (sem internet, tempo esgotado...).
final class TranscriptNetworkError extends TranscriptError {
  const TranscriptNetworkError(super.videoId, this.cause);
  final Object cause;
  @override
  String get name => 'ConnectionError';
  @override
  String toString() => '$name($videoId, $cause)';
}

/// Uma faixa de legenda do vídeo.
class CaptionTrack {
  const CaptionTrack({
    required this.videoId,
    required this.url,
    required this.language,
    required this.languageCode,
    required this.isGenerated,
  });

  final String videoId;

  /// Endereço da faixa, já sem `&fmt=srv3` (vem no formato XML simples).
  final String url;

  /// Nome como o YouTube mostra, ex. "English (auto-generated)".
  final String language;

  /// Código do YouTube, ex. "en", "pt-BR", "es-419".
  final String languageCode;

  /// Gerada automaticamente (reconhecimento de voz, `kind: asr`).
  final bool isGenerated;

  @override
  String toString() => '$languageCode${isGenerated ? '(auto)' : ''}';
}

class TranscriptApi {
  TranscriptApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, String> _cookies = {};

  /// Faixas de legenda do vídeo: primeiro as feitas por pessoas, depois as
  /// geradas automaticamente (a ordem do `TranscriptList` do Python).
  Future<List<CaptionTrack>> list(String videoId) async {
    final html = await _fetchVideoHtml(videoId);
    final apiKey = _extractInnertubeApiKey(html, videoId);
    final data = await _fetchInnertubeData(videoId, apiKey);
    return _buildTracks(videoId, _extractCaptionsJson(data, videoId));
  }

  /// As falas da faixa, na ordem em que aparecem.
  Future<List<Cue>> fetch(CaptionTrack track) async {
    if (track.url.contains('&exp=xpe')) throw PoTokenRequired(track.videoId);
    final body = await _send(
      () => _client.get(Uri.parse(track.url), headers: _headers()),
      track.videoId,
    );
    return parseTranscript(body);
  }

  void close() => _client.close();

  // ---- página do vídeo -------------------------------------------------------

  Future<String> _fetchVideoHtml(String videoId) async {
    var html = await _fetchHtml(videoId);
    if (html.contains(_consentForm)) {
      _createConsentCookie(html, videoId);
      html = await _fetchHtml(videoId);
      if (html.contains(_consentForm)) throw FailedToCreateConsentCookie(videoId);
    }
    return html;
  }

  Future<String> _fetchHtml(String videoId) async {
    final body = await _send(
      () => _client.get(Uri.parse('$watchUrl$videoId'), headers: _headers()),
      videoId,
    );
    return unescapeHtml(body);
  }

  void _createConsentCookie(String html, String videoId) {
    final m = RegExp(r'name="v" value="(.*?)"').firstMatch(html);
    if (m == null) throw FailedToCreateConsentCookie(videoId);
    _cookies['CONSENT'] = 'YES+${m[1]}';
  }

  String _extractInnertubeApiKey(String html, String videoId) {
    final m = RegExp(r'"INNERTUBE_API_KEY":\s*"([a-zA-Z0-9_-]+)"').firstMatch(html);
    if (m != null) return m[1]!;
    if (html.contains('class="g-recaptcha"')) throw IpBlocked(videoId);
    throw YouTubeDataUnparsable(videoId);
  }

  // ---- InnerTube ---------------------------------------------------------------

  Future<Map<String, dynamic>> _fetchInnertubeData(String videoId, String apiKey) async {
    final body = await _send(
      () => _client.post(
        Uri.parse('$innertubeApiUrl$apiKey'),
        headers: {..._headers(), 'Content-Type': 'application/json'},
        body: jsonEncode({'context': innertubeContext, 'videoId': videoId}),
      ),
      videoId,
    );
    try {
      final data = jsonDecode(body);
      if (data is Map<String, dynamic>) return data;
    } on FormatException {
      // cai no erro abaixo
    }
    throw YouTubeDataUnparsable(videoId);
  }

  Map<String, dynamic> _extractCaptionsJson(Map<String, dynamic> data, String videoId) {
    _assertPlayability(data['playabilityStatus'], videoId);
    final captions = data['captions'];
    final renderer = captions is Map ? captions['playerCaptionsTracklistRenderer'] : null;
    if (renderer is! Map<String, dynamic> || renderer['captionTracks'] is! List) {
      throw TranscriptsDisabled(videoId);
    }
    return renderer;
  }

  void _assertPlayability(Object? statusData, String videoId) {
    if (statusData is! Map) return;
    final status = statusData['status'];
    if (status == null || status == 'OK') return;
    final reason = statusData['reason'] is String ? statusData['reason'] as String : null;
    if (status == 'LOGIN_REQUIRED') {
      if (reason == _botDetected) throw RequestBlocked(videoId);
      if (reason == _ageRestricted) throw AgeRestricted(videoId);
    }
    if (status == 'ERROR' && reason == _videoUnavailable) {
      if (videoId.startsWith('http://') || videoId.startsWith('https://')) {
        throw InvalidVideoId(videoId);
      }
      throw VideoUnavailable(videoId);
    }
    final runs = _dig(statusData, ['errorScreen', 'playerErrorMessageRenderer', 'subreason', 'runs']);
    throw VideoUnplayable(videoId, reason, [
      if (runs is List)
        for (final run in runs)
          if (run is Map) '${run['text'] ?? ''}',
    ]);
  }

  List<CaptionTrack> _buildTracks(String videoId, Map<String, dynamic> captions) {
    final manual = <String, CaptionTrack>{};
    final generated = <String, CaptionTrack>{};
    for (final caption in captions['captionTracks'] as List) {
      if (caption is! Map) continue;
      final code = caption['languageCode'];
      final url = caption['baseUrl'];
      if (code is! String || url is! String) continue;
      final asr = caption['kind'] == 'asr';
      (asr ? generated : manual)[code] = CaptionTrack(
        videoId: videoId,
        url: url.replaceAll('&fmt=srv3', ''),
        language: _trackName(caption['name']) ?? code,
        languageCode: code,
        isGenerated: asr,
      );
    }
    return [...manual.values, ...generated.values];
  }

  static String? _trackName(Object? name) {
    if (name is! Map) return null;
    final runs = name['runs'];
    if (runs is List && runs.isNotEmpty && runs.first is Map && runs.first['text'] is String) {
      return runs.first['text'] as String;
    }
    return name['simpleText'] is String ? name['simpleText'] as String : null;
  }

  static Object? _dig(Object? data, List<String> path) {
    var cur = data;
    for (final key in path) {
      if (cur is! Map) return null;
      cur = cur[key];
    }
    return cur;
  }

  // ---- HTTP ----------------------------------------------------------------------

  /// O pacote Python manda só `Accept-Language: en-US` (os textos de erro que ele
  /// reconhece são em inglês) e os cookies da sessão.
  Map<String, String> _headers() => {
        'Accept-Language': 'en-US',
        if (_cookies.isNotEmpty)
          'Cookie': _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
      };

  Future<String> _send(Future<http.Response> Function() request, String videoId) async {
    final http.Response r;
    try {
      r = await request().timeout(requestTimeout);
    } on Exception catch (e) {
      throw TranscriptNetworkError(videoId, e);
    }
    _storeCookies(r.headers['set-cookie']);
    if (r.statusCode == 429) throw IpBlocked(videoId);
    if (r.statusCode >= 400) throw YouTubeRequestFailed(videoId, r.statusCode);
    return utf8.decode(r.bodyBytes, allowMalformed: true);
  }

  // O pacote http junta vários Set-Cookie com vírgulas; a data do Expires também
  // tem vírgula, mas depois dela não vem "nome=".
  static final RegExp _cookieSplit = RegExp(r',(?=\s*[^;,=\s]+=)');

  void _storeCookies(String? header) {
    if (header == null || header.isEmpty) return;
    for (final part in header.split(_cookieSplit)) {
      final pair = part.split(';').first.trim();
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final name = pair.substring(0, eq).trim();
      final value = pair.substring(eq + 1).trim();
      if (value.isEmpty) {
        _cookies.remove(name);
      } else {
        _cookies[name] = value;
      }
    }
  }
}

final RegExp _textElement = RegExp(r'<text\b([^>]*?)(?:/>|>([\s\S]*?)</text>)');
final RegExp _pElement = RegExp(r'<p\b([^>]*?)(?:/>|>([\s\S]*?)</p>)');
final RegExp _tags = RegExp(r'<[^>]*>');

/// Lê a legenda em XML: `<transcript><text start="1.2" dur="3.4">...</text>`.
/// O texto vem com as entidades escapadas duas vezes e às vezes com tags
/// (`<font color=...>`), que saem. Também entende o formato srv3
/// (`<p t="1200" d="3400">`, em milissegundos), se o YouTube mandar esse.
List<Cue> parseTranscript(String xml) {
  final cues = <Cue>[];
  for (final m in _textElement.allMatches(xml)) {
    final raw = m[2];
    if (raw == null || raw.isEmpty) continue; // como o ElementTree: sem texto, sem fala
    final start = _number(m[1]!, 'start');
    if (start == null) continue;
    cues.add(Cue(start, _number(m[1]!, 'dur') ?? 0, _plain(raw)));
  }
  if (cues.isNotEmpty || !xml.contains('<timedtext')) return cues;

  for (final m in _pElement.allMatches(xml)) {
    final raw = m[2];
    final t = _number(m[1]!, 't');
    if (raw == null || t == null) continue;
    final text = _plain(raw);
    if (text.trim().isEmpty) continue;
    cues.add(Cue(t / 1000, (_number(m[1]!, 'd') ?? 0) / 1000, text));
  }
  return cues;
}

String _plain(String raw) => unescapeHtml(unescapeHtml(raw)).replaceAll(_tags, '');

double? _number(String attributes, String name) {
  final m = RegExp('\\b$name="([^"]*)"').firstMatch(attributes);
  return m == null ? null : double.tryParse(m[1]!);
}
