/// Tradução das falas, sempre 1:1 (uma tradução para cada fala, para casar com
/// os tempos). Porte do tradutor.py.
///
/// Primeiro o Google Tradutor gratuito (translate.googleapis.com, cliente
/// "gtx"), em até três modos:
///  1. Google: as falas vão num texto só, uma por linha. É o modo com mais
///     contexto, mas às vezes o Google junta duas falas numa linha e o lote
///     deixa de casar com os tempos.
///  2. Google (itens): o mesmo lote num pedido só, com cada fala num item
///     separado (translate_a/t). A resposta traz sempre uma tradução por item;
///     só se perde o contexto entre uma fala e outra.
///  3. Google (fala por fala): um pedido por fala, mais lento. Só entra quando
///     os modos 1 e 2 falham e um deles desalinhou (sinal de que o Google está
///     respondendo).
/// Sem conexão ou com o limite de uso atingido (HTTP 429), os outros modos do
/// Google nem são tentados.
///
/// Bloqueio do Google (HTTP 429): nenhum pedido sai até passar a espera, para
/// não prolongar o bloqueio. A espera é a do cabeçalho Retry-After, se vier;
/// senão 2, 5, 10 e depois 15 min a cada 429 seguido. Quem chama recebe
/// [RateLimited], com a hora em que vale tentar de novo. Depois do primeiro
/// bloqueio, os pedidos passam a sair no máximo 1 a cada 2 s.
///
/// Reserva, só quando o Google falha: MyMemory (api.mymemory.translated.net),
/// sem chave e sem e-mail.
///  - Cota de 5.000 caracteres por dia e no máximo 500 bytes por pedido. As
///    falas vão em lotes de até 500 bytes, uma por linha; se a contagem de
///    linhas não bater, o lote é dividido ao meio até casar.
///  - Não detecta o idioma: precisa do código da legenda.
///  - Quando a cota acaba, fica de fora até a hora em que o MyMemory diz que
///    ela volta.
///  - No máximo 1 pedido por segundo.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpDate;
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../core/log.dart';
import '../core/text.dart';

/// (conectar, ler) = (6, 20) s no Python; aqui o tempo total do pedido.
const Duration timeout = Duration(seconds: 26);
const String userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
const String googleHost = 'translate.googleapis.com';
const String googlePath = '/translate_a/single'; // um texto -> trechos traduzidos
const String googleItemsPath = '/translate_a/t'; // vários "q" -> uma tradução por "q"
const List<int> blockWaits = [120, 300, 600, 900]; // s após o 1º, 2º, 3º, 4º+ 429 seguidos
const Duration paceAfterBlock = Duration(seconds: 2);
const String myMemoryHost = 'api.mymemory.translated.net';
const int myMemoryMaxBytes = 500; // tamanho máximo do "q" (UTF-8)
const Duration myMemoryPace = Duration(seconds: 1);
const int myMemoryDailyChars = 5000; // cota grátis por dia, sem e-mail (só para as mensagens)

/// Falha ao traduzir. A mensagem já vem pronta para mostrar ao usuário.
class TranslateError implements Exception {
  TranslateError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// O tradutor juntou ou quebrou falas, então não dá para casar com os tempos.
class Misaligned extends TranslateError {
  Misaligned(super.message);
}

/// Sem conexão ou limite de uso atingido: outro modo do mesmo serviço também falharia.
class Unavailable extends TranslateError {
  Unavailable(super.message);
}

/// O Google barrou este IP por excesso de pedidos (HTTP 429). Nenhum pedido sai antes de [until].
class RateLimited extends Unavailable {
  RateLimited(String who, this.until) : super('$who: limite de uso atingido (HTTP 429)');

  /// A partir de quando vale tentar de novo.
  final DateTime until;

  /// Por que a reserva (MyMemory) também não traduziu, se foi tentada.
  String fallback = '';
}

/// A cota grátis do MyMemory acabou: nenhum pedido sai antes de [until].
class QuotaExceeded extends TranslateError {
  QuotaExceeded(this.until, {DateTime? now})
      : super('MyMemory (reserva): a cota grátis do dia acabou; volta ${clock(until, now: now)}');
  final DateTime until;
}

/// "às 15:30", "amanhã às 09:12" ou "em 12/11 às 09:12".
String clock(DateTime at, {DateTime? now}) {
  final t = at.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  final hm = hourMinute(t);
  if (sameDay(t, today)) return 'às $hm';
  if (sameDay(t, today.add(const Duration(days: 1)))) return 'amanhã às $hm';
  String two(int n) => n.toString().padLeft(2, '0');
  return 'em ${two(t.day)}/${two(t.month)} às $hm';
}

/// Segundos pedidos no cabeçalho Retry-After (em segundos ou como data HTTP).
double? parseRetryAfter(String? value, DateTime now) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return null;
  final seconds = double.tryParse(v);
  if (seconds != null) return seconds.isNaN ? null : seconds;
  try {
    return HttpDate.parse(v).difference(now).inMilliseconds / 1000;
  } catch (_) {
    return null;
  }
}

// Códigos de legenda do YouTube que o MyMemory escreve de outro jeito.
const Map<String, String> _mmCodes = {
  'zh-hans': 'zh-CN', 'zh-hant': 'zh-TW', 'zh-tw': 'zh-TW', 'zh-hk': 'zh-TW',
  'zh': 'zh-CN', 'iw': 'he', 'in': 'id', 'ji': 'yi', 'jw': 'jv', 'pt': 'pt-BR',
};

/// Código de idioma do YouTube ("en-US", "es-419", "zh-Hans"...) no formato do
/// MyMemory. `null` para "auto" ou vazio: o MyMemory não detecta o idioma sozinho.
String? myMemoryLang(String? code) {
  if (code == null || code.isEmpty || code.toLowerCase() == 'auto') return null;
  final low = code.toLowerCase();
  final base = low.split('-').first;
  return _mmCodes[low] ?? _mmCodes[base] ?? base;
}

/// Junta falas seguidas em grupos que, unidos por quebra de linha, cabem em
/// [limit] bytes (UTF-8).
List<List<String>> byteGroups(List<String> lines, int limit) {
  final groups = <List<String>>[];
  var cur = <String>[];
  var size = 0;
  for (final t in lines) {
    final n = utf8.encode(t).length;
    if (cur.isNotEmpty && size + 1 + n > limit) {
      groups.add(cur);
      cur = <String>[];
      size = 0;
    }
    size += n + (cur.isNotEmpty ? 1 : 0);
    cur.add(t);
  }
  if (cur.isNotEmpty) groups.add(cur);
  return groups;
}

typedef Engine = Future<List<String>> Function(List<String> lines, String src, String tgt);

final RegExp _newline = RegExp(r'\r?\n');
final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

/// Os serviços de tradução e o estado que vale para o app todo (todos os
/// vídeos): o bloqueio do Google e a cota do MyMemory.
class TranslationService {
  TranslationService({
    http.Client? client,
    DateTime Function()? now,
    Future<void> Function(Duration)? sleep,
  })  : _client = client ?? http.Client(),
        _now = now ?? DateTime.now,
        _sleep = sleep ?? _delay;

  static Future<void> _delay(Duration d) => Future<void>.delayed(d);

  final http.Client _client;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;

  // Bloqueio do Google (HTTP 429).
  DateTime _until = _epoch;
  int _strikes = 0;
  bool _paced = false;
  DateTime _next = _epoch;

  // MyMemory: a cota acabou até _mmUntil; o próximo pedido não sai antes de _mmNext.
  DateTime _mmUntil = _epoch;
  DateTime _mmNext = _epoch;

  /// Até quando o Google está bloqueando (no passado se não está).
  DateTime get googleBlockedUntil => _until;

  /// Modos do Google tentados em ordem a cada lote (o diagnóstico testa cada um).
  /// O modo 3 (fala por fala) fica de fora: só entra no fim, se o Google
  /// responder mas desalinhar.
  late final Map<String, Engine> engines = {'Google': googleBatch, 'Google (itens)': googleItems};

  /// Só quando o Google falha.
  late final Map<String, Engine> reserve = {'MyMemory (reserva)': myMemoryBatch};

  // ---- HTTP -------------------------------------------------------------------

  /// Antes de cada pedido: recusa se o Google está bloqueando; depois de um
  /// bloqueio, espaça os pedidos.
  Future<void> _waitTurn(String who) async {
    final now = _now();
    if (now.isBefore(_until)) throw RateLimited(who, _until);
    final start = _paced && _next.isAfter(now) ? _next : now;
    _next = start.add(paceAfterBlock);
    if (start.isAfter(now)) {
      await _sleep(start.difference(now));
      // outro pedido levou 429 enquanto este esperava a vez
      if (_now().isBefore(_until)) throw RateLimited(who, _until);
    }
  }

  /// Anota o HTTP 429 e devolve o erro com a hora da próxima tentativa.
  RateLimited _blocked(String who, String? retryAfter) {
    final now = _now();
    if (!now.isBefore(_until)) {
      // 429 novo (não de um pedido que saiu antes do bloqueio já anotado)
      _strikes++;
      final wait = parseRetryAfter(retryAfter, now) ??
          blockWaits[math.min(_strikes, blockWaits.length) - 1].toDouble();
      final seconds = wait.isFinite ? wait.clamp(5.0, 3600.0) : 3600.0;
      _until = now.add(Duration(milliseconds: (seconds * 1000).round()));
      _paced = true;
    }
    return RateLimited(who, _until);
  }

  /// Manda o pedido; sem resposta (sem conexão, tempo esgotado...) vira [Unavailable].
  Future<http.Response> _send(
    String method,
    Uri url,
    String who, {
    Map<String, String>? headers,
    String? body,
  }) async {
    final h = {'User-Agent': userAgent, ...?headers};
    try {
      final request = method == 'POST'
          ? _client.post(url, headers: h, body: body)
          : _client.get(url, headers: h);
      return await request.timeout(timeout);
    } on TimeoutException {
      throw Unavailable('$who: falha de conexão (tempo esgotado)');
    } on Exception catch (e) {
      throw Unavailable('$who: falha de conexão (${e is http.ClientException ? 'sem resposta' : e.runtimeType})');
    }
  }

  /// Pedido ao Google, respeitando o bloqueio (HTTP 429).
  Future<http.Response> _request(
    String method,
    Uri url,
    String who, {
    Map<String, String>? headers,
    String? body,
  }) async {
    await _waitTurn(who);
    final r = await _send(method, url, who, headers: headers, body: body);
    if (r.statusCode == 429) {
      final err = _blocked(who, r.headers['retry-after']);
      Log.warning('$err; nenhum pedido ao Google antes das ${_hms(err.until)}');
      throw err;
    }
    _strikes = 0; // o Google voltou a responder: o próximo 429 recomeça pela espera menor
    if (r.statusCode >= 400) {
      Log.warning('$who HTTP ${r.statusCode}: ${_head(r)}');
      throw TranslateError('$who: HTTP ${r.statusCode}');
    }
    return r;
  }

  static String _text(http.Response r) => utf8.decode(r.bodyBytes, allowMalformed: true);

  static String _head(http.Response r) {
    final t = _text(r);
    return jsonEncode(t.length > 300 ? t.substring(0, 300) : t);
  }

  static String _hms(DateTime t) {
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
  }

  // ---- Google -----------------------------------------------------------------

  Future<String> googleText(String text, String src, String tgt, {String who = 'Google'}) async {
    final r = await _request(
      'GET',
      Uri.https(googleHost, googlePath, {
        'client': 'gtx', 'sl': src, 'tl': tgt, 'dt': 't',
        'ie': 'UTF-8', 'oe': 'UTF-8', 'q': text,
      }),
      who,
    );
    try {
      final data = jsonDecode(_text(r)) as List;
      return [
        for (final seg in data[0] as List)
          if (seg is List && seg.isNotEmpty && seg[0] is String) seg[0] as String,
      ].join();
    } catch (_) {
      Log.warning('$who: resposta inesperada: ${_head(r)}');
      throw TranslateError('$who: resposta em formato inesperado');
    }
  }

  /// Modo 1: as falas num texto só, uma por linha.
  Future<List<String>> googleBatch(List<String> lines, String src, String tgt) async {
    final out = await googleText(lines.join('\n'), src, tgt);
    final parts = [for (final p in out.trim().split(_newline)) oneLine(p)];
    if (parts.length != lines.length) {
      throw Misaligned('Google: enviei ${lines.length} falas e voltaram ${parts.length}');
    }
    return parts;
  }

  /// Modo 2: o lote num pedido só, com cada fala num "q" separado.
  Future<List<String>> googleItems(List<String> lines, String src, String tgt) async {
    const who = 'Google (itens)';
    final r = await _request(
      'POST',
      Uri.https(googleHost, googleItemsPath, {'client': 'gtx', 'sl': src, 'tl': tgt}),
      who,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: lines.map((t) => 'q=${Uri.encodeQueryComponent(t)}').join('&'),
    );
    final List<String> texts;
    try {
      final data = jsonDecode(_text(r));
      if (data is! List) throw const FormatException('esperava uma lista');
      // idioma de origem fixo: ["tradução", ...]; "auto": [["tradução", "idioma"], ...]
      final items = [for (final item in data) item is List && item.isNotEmpty ? item[0] : item];
      if (!items.every((t) => t is String)) throw const FormatException('esperava só textos');
      texts = items.cast<String>();
    } catch (_) {
      Log.warning('$who: resposta inesperada: ${_head(r)}');
      throw TranslateError('$who: resposta em formato inesperado');
    }
    if (texts.length != lines.length) {
      throw Misaligned('$who: enviei ${lines.length} falas e voltaram ${texts.length}');
    }
    return [for (final t in texts) oneLine(t)];
  }

  /// Modo 3: um pedido por fala (4 de cada vez).
  Future<List<String>> googleOneByOne(List<String> lines, String src, String tgt) async {
    final out = List<String?>.filled(lines.length, null);
    var next = 0;
    TranslateError? failure;
    Future<void> worker() async {
      // deu erro: não manda os pedidos que ainda estão na fila
      while (failure == null && next < lines.length) {
        final i = next++;
        try {
          out[i] = oneLine(await googleText(lines[i], src, tgt, who: 'Google (fala por fala)'));
        } on TranslateError catch (e) {
          failure ??= e;
        }
      }
    }

    await Future.wait([for (var w = 0; w < math.min(4, lines.length); w++) worker()]);
    final error = failure;
    if (error != null) throw error;
    return out.cast<String>();
  }

  // ---- MyMemory (reserva) -----------------------------------------------------

  /// Antes de cada pedido ao MyMemory: recusa se a cota acabou; no máximo 1 pedido por segundo.
  Future<void> _myMemoryTurn() async {
    final now = _now();
    if (now.isBefore(_mmUntil)) throw QuotaExceeded(_mmUntil, now: now);
    final start = _mmNext.isAfter(now) ? _mmNext : now;
    _mmNext = start.add(myMemoryPace);
    if (start.isAfter(now)) await _sleep(start.difference(now));
  }

  static final RegExp _nextAvailable = RegExp(
    r'NEXT AVAILABLE IN\s*((?:\d+\s*(?:HOUR|MINUTE|SECOND)S?\s*)+)',
    caseSensitive: false,
  );
  static final RegExp _unit = RegExp(r'(\d+)\s*(HOUR|MINUTE|SECOND)', caseSensitive: false);

  /// Anota que a cota acabou, até a hora do aviso
  /// ("NEXT AVAILABLE IN 10 HOURS 20 MINUTES 33 SECONDS").
  QuotaExceeded _quotaOver(String warning) {
    const units = {'HOUR': 3600, 'MINUTE': 60, 'SECOND': 1};
    final m = _nextAvailable.firstMatch(warning);
    var wait = 0;
    for (final u in _unit.allMatches(m?[1] ?? '')) {
      wait += int.parse(u[1]!) * units[u[2]!.toUpperCase()]!;
    }
    final now = _now();
    final until = now.add(Duration(seconds: math.max(wait == 0 ? 3600 : wait, 60))); // sem hora: 1 h
    if (until.isAfter(_mmUntil)) _mmUntil = until;
    final err = QuotaExceeded(_mmUntil, now: now);
    Log.warning('$err');
    return err;
  }

  static bool _truthy(Object? v) => v != null && v != false && v != 0 && v != '';

  /// Um pedido ao MyMemory (até 500 bytes). [src] e [tgt] já no formato do MyMemory.
  Future<String> myMemoryText(String text, String src, String tgt) async {
    const who = 'MyMemory (reserva)';
    await _myMemoryTurn();
    final r = await _send('GET', Uri.https(myMemoryHost, '/get', {'q': text, 'langpair': '$src|$tgt'}), who);
    Object? data;
    try {
      data = jsonDecode(_text(r));
    } on FormatException {
      data = null;
    }
    if (data is! Map) {
      if (r.statusCode == 429) throw _quotaOver('');
      Log.warning('$who HTTP ${r.statusCode}: ${_head(r)}');
      throw TranslateError(
        r.statusCode >= 400 ? '$who: HTTP ${r.statusCode}' : '$who: resposta em formato inesperado',
      );
    }
    final responseData = data['responseData'];
    final found = responseData is Map ? responseData['translatedText'] : null;
    final details = _truthy(data['responseDetails']) ? '${data['responseDetails']}' : '';
    final rawStatus = data['responseStatus'];
    final status = rawStatus is num
        ? (rawStatus == 0 ? r.statusCode : rawStatus.toInt())
        : (_truthy(rawStatus) ? int.tryParse('$rawStatus') : null) ?? r.statusCode;
    // o HTTP pode vir 200 com o erro dentro do JSON, e aí translatedText é a própria mensagem de erro
    final warning = '$details ${found is String ? found : ''}';
    if (_truthy(data['quotaFinished']) ||
        status == 429 ||
        r.statusCode == 429 ||
        warning.toUpperCase().contains('USED ALL AVAILABLE FREE TRANSLATIONS')) {
      throw _quotaOver(warning);
    }
    if (status != 200 || r.statusCode >= 400 || found is! String) {
      Log.warning('$who: status $status: ${jsonEncode(warning.length > 300 ? warning.substring(0, 300) : warning)}');
      final shown = details.length > 120 ? details.substring(0, 120) : details;
      throw TranslateError('$who: ${shown.isEmpty ? 'resposta sem tradução' : shown} (status $status)');
    }
    return unescapeHtml(found);
  }

  /// Um lote, uma fala por linha. Se a contagem não bater, divide ao meio (no
  /// fim, uma fala por pedido).
  Future<List<String>> _myMemoryLines(List<String> lines, String src, String tgt) async {
    final out = await myMemoryText(lines.join('\n'), src, tgt);
    if (lines.length == 1) return [oneLine(out)];
    final parts = [for (final p in out.trim().split(_newline)) oneLine(p)];
    if (parts.length == lines.length) return parts;
    Log.info('MyMemory (reserva): enviei ${lines.length} falas e voltaram ${parts.length}; dividindo o lote');
    final mid = lines.length ~/ 2;
    return [
      ...await _myMemoryLines(lines.sublist(0, mid), src, tgt),
      ...await _myMemoryLines(lines.sublist(mid), src, tgt),
    ];
  }

  /// Reserva: as falas em lotes de até 500 bytes, sempre uma tradução por fala.
  /// [src] e [tgt] como no resto do app ("en", "pt", ou o código da legenda, ex. "es-419").
  Future<List<String>> myMemoryBatch(List<String> lines, String src, String tgt) async {
    final from = myMemoryLang(src), to = myMemoryLang(tgt);
    if (from == null || to == null) {
      throw TranslateError('MyMemory (reserva): precisa saber o idioma de origem da legenda');
    }
    final out = <String>[];
    for (final group in byteGroups(lines, myMemoryMaxBytes)) {
      out.addAll(await _myMemoryLines(group, from, to));
    }
    return out;
  }
}

/// Tradutor de um vídeo: tenta o Google e, se ele falhar, a reserva.
class Translator {
  /// [src]: origem para o Google ("en", "pt" ou "auto"); [tgt]: "pt" ou "en".
  /// [sourceLang]: código da legenda no YouTube (ex. "es-419"), para a reserva,
  /// que não detecta o idioma.
  Translator(this.service, this.src, this.tgt, {String? sourceLang}) : sourceLang = sourceLang ?? src;

  final TranslationService service;
  final String src;
  final String tgt;
  final String sourceLang;

  /// Serviços que traduziram algum lote (vai na mensagem final).
  final Set<String> used = {};

  /// Quem traduziu o último lote: "Google" ou "MyMemory".
  String last = '';

  /// O último lote foi para a reserva porque o Google está bloqueando.
  bool googleBlocked = false;

  /// Uma tradução por fala, na mesma ordem, ou [TranslateError].
  /// Se o Google está bloqueando e a reserva também não traduziu, lança
  /// [RateLimited]: `until` diz quando tentar o Google e `fallback`, por que a
  /// reserva não serviu.
  Future<List<String>> translate(List<String> lines) async {
    List<String> out;
    String who;
    try {
      out = await _google(lines);
      who = 'Google';
    } on TranslateError catch (e) {
      out = await _reserve(lines, e);
      who = 'MyMemory';
      googleBlocked = e is RateLimited;
    }
    last = who;
    used.add(who);
    return out;
  }

  Future<List<String>> _reserve(List<String> lines, TranslateError googleError) async {
    final List<String> out;
    try {
      out = await service.myMemoryBatch(lines, sourceLang, tgt);
      if (!out.any((t) => t.isNotEmpty)) {
        throw TranslateError('MyMemory (reserva): a tradução veio vazia');
      }
    } on TranslateError catch (e) {
      if (e is! QuotaExceeded) Log.warning('$e'); // cota: o aviso já foi para o registro uma vez
      if (googleError is RateLimited) {
        googleError.fallback = e.message;
        throw googleError;
      }
      throw TranslateError('$googleError · $e');
    }
    Log.info('MyMemory (reserva): lote de ${lines.length} falas traduzido ($googleError)');
    return out;
  }

  Future<List<String>> _google(List<String> lines) async {
    final errors = <String>[];
    var misaligned = false;
    for (final MapEntry(key: name, value: engine) in service.engines.entries) {
      final List<String> out;
      try {
        out = await engine(lines, src, tgt);
        if (!out.any((t) => t.isNotEmpty)) throw TranslateError('$name: a tradução veio vazia');
      } on Unavailable catch (e) {
        // mesmo serviço: tentar outro modo só gastaria mais pedidos
        if (e is! RateLimited) Log.warning('$e'); // o 429 já foi para o registro quando chegou
        rethrow;
      } on TranslateError catch (e) {
        misaligned |= e is Misaligned;
        Log.warning('$e');
        errors.add(e.message);
        continue;
      }
      if (errors.isNotEmpty) Log.info('$name: lote de ${lines.length} falas traduzido');
      return out;
    }

    if (misaligned) {
      // o Google responde, só não manteve as falas separadas
      try {
        return await service.googleOneByOne(lines, src, tgt);
      } on Unavailable catch (e) {
        if (e is! RateLimited) Log.warning('$e');
        rethrow;
      } on TranslateError catch (e) {
        Log.warning('$e');
        errors.add(e.message);
      }
    }
    throw TranslateError(errors.join(' · '));
  }
}
