/// O vídeo aberto, a legenda dele e a tradução (a classe `Api` do app.py).
///
/// Cada [load] começa um "job" novo; o trabalho de um job antigo para sozinho
/// na próxima vez que confere [_alive].
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/cue.dart';
import '../core/log.dart';
import '../core/subtitles.dart';
import '../core/text.dart';
import '../data/history.dart';
import '../data/translation_cache.dart';
import '../translation/translator.dart';
import '../youtube/oembed.dart';
import '../youtube/transcript_api.dart';
import '../youtube/video_id.dart';

class LoadResult {
  const LoadResult.ok(String this.videoId) : error = null;
  const LoadResult.error(String this.error) : videoId = null;
  final String? videoId;
  final String? error;
  bool get ok => videoId != null;
}

class SubtitleSession extends ChangeNotifier {
  SubtitleSession({
    required this.history,
    required this.cache,
    required this.transcripts,
    required this.translation,
    required this.client,
  });

  final History history;
  final TranslationCache cache;
  final TranscriptApi transcripts;
  final TranslationService translation;
  final http.Client client;

  int _job = 0;
  int _focus = 0;
  String? _vid; // vídeo aberto por último
  bool _disposed = false;

  // ---- o que a interface mostra ----
  String? videoId;
  String source = 'auto';
  SubtitleMeta? meta;

  /// Tradução de cada fala (mesmo índice de [cues]); null enquanto não chegou.
  List<String?> translations = const [];
  int translated = 0;
  int toTranslate = 0;
  String status = '';
  bool statusError = false;

  /// Ainda buscando a legenda ou traduzindo.
  bool busy = false;

  List<Cue> get cues => meta?.cues ?? const [];
  int get job => _job;

  // ---- chamados pela interface ----

  /// Abre o vídeo e começa a buscar a legenda. [keepPlace]: o vídeo foi aberto
  /// pela lista de recentes e fica no lugar dele.
  LoadResult load(String url, {String source = 'auto', bool keepPlace = false}) {
    final vid = extractVideoId(url);
    if (vid == null) return const LoadResult.error('Link do YouTube inválido.');
    source = normalizeSource(source);
    final job = ++_job;
    _focus = 0;
    // o mesmo vídeo de novo (trocou o idioma, nova tentativa) também não muda de lugar
    keepPlace = keepPlace || vid == _vid;
    _vid = vid;

    videoId = vid;
    this.source = source;
    meta = null;
    translations = const [];
    translated = 0;
    toTranslate = 0;
    status = '';
    statusError = false;
    busy = true;
    notifyListeners();

    unawaited(_run(job, vid, source));
    if (history.opened(vid, source, keepPlace: keepPlace)) unawaited(_fetchTitle(vid));
    return LoadResult.ok(vid);
  }

  /// A interface avisa onde o vídeo está, para traduzir esse trecho primeiro.
  void focus(int job, int index) {
    if (job == _job) _focus = index;
  }

  /// A interface avisa onde o vídeo está, para retomar dali depois.
  void progress(String videoId, double seconds, double duration) {
    if (!isVideoId(videoId) || !seconds.isFinite || !duration.isFinite) return;
    if (seconds < 0 || seconds >= 1e7 || duration < 0 || duration >= 1e7) return;
    history.update(
      videoId,
      pos: (seconds * 10).roundToDouble() / 10,
      dur: (duration * 10).roundToDouble() / 10,
    );
    history.save(force: false);
  }

  @override
  void dispose() {
    _disposed = true;
    _job++;
    super.dispose();
  }

  // ---- internos ----

  bool _alive(int job) => !_disposed && job == _job;

  void _setStatus(int job, String message, {bool error = false}) {
    if (!_alive(job)) return;
    status = message;
    statusError = error;
    notifyListeners();
  }

  void _onTranscript(int job, SubtitleMeta m) {
    if (!_alive(job)) return;
    meta = m;
    translations = List<String?>.filled(m.cues.length, null);
    translated = 0;
    toTranslate = m.cues.where((c) => c.text.isNotEmpty).length;
    notifyListeners();
  }

  void _onTranslations(int job, List<(int, String)> pairs) {
    final m = meta;
    if (!_alive(job) || m == null) return;
    for (final (i, text) in pairs) {
      if (i < 0 || i >= translations.length) continue;
      if (translations[i] == null) translated++;
      translations[i] = text;
    }
    if (toTranslate > 0) {
      status = 'Traduzindo para ${m.targetName}… ${(100 * translated / toTranslate).round()}%';
      statusError = false;
    }
    notifyListeners();
  }

  Future<void> _fetchTitle(String vid) async {
    final (title, author) = await videoTitle(client, vid);
    if (title.isNotEmpty) {
      history.update(vid, title: title, author: author);
      history.save();
    }
  }

  Future<bool> _sleep(int job, Duration duration) async {
    const tick = Duration(milliseconds: 250);
    final end = DateTime.now().add(duration);
    while (true) {
      if (!_alive(job)) return false;
      final left = end.difference(DateTime.now());
      if (left <= Duration.zero) return true;
      await Future<void>.delayed(left < tick ? left : tick);
    }
  }

  /// O Google bloqueou (HTTP 429) e a reserva não deu conta ([fallback] diz por
  /// quê): espera sem mandar pedidos e mostra quando tenta o Google de novo.
  Future<bool> _waitBlock(int job, DateTime until, String fallback) async {
    while (true) {
      final left = until.difference(DateTime.now()).inMilliseconds / 1000;
      if (left <= 0) return _alive(job);
      final mins = left < 60 ? 'menos de 1 min' : '${((left + 59) / 60).floor()} min';
      final reserve = fallback.isNotEmpty ? ' $fallback.' : '';
      _setStatus(
        job,
        'O Google bloqueou temporariamente as traduções por excesso de pedidos (HTTP 429).'
        '$reserve Nova tentativa no Google às ${hourMinute(until)} (em $mins); '
        'a tradução continua sozinha.',
        error: true,
      );
      final step = Duration(milliseconds: (math.min(left, 15) * 1000).round());
      if (!await _sleep(job, step)) return false;
    }
  }

  int _nextChunk(List<int> pending, List<List<(int, String)>> chunks) {
    final after = pending.where((c) => chunks[c].last.$1 >= _focus);
    return (after.isNotEmpty ? after : pending).reduce(math.min);
  }

  Future<void> _run(int job, String vid, String source) async {
    try {
      await _work(job, vid, source);
    } catch (e, stack) {
      Log.warning('Erro inesperado em $vid: $e\n$stack');
      _setStatus(job, 'Erro inesperado: $e', error: true);
    } finally {
      if (_alive(job)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _work(int job, String vid, String source) async {
    final cached = await cache.get(vid, source);
    if (cached != null) {
      if (!_alive(job)) return;
      _onTranscript(job, cached.meta);
      _onTranslations(job, cached.pairs);
      _setStatus(job, cached.doneMessage);
      return;
    }

    // 1) legenda original
    final CaptionTrack track;
    final List<Cue> cues;
    try {
      _setStatus(job, 'Buscando legendas…');
      track = pickTranscript(await transcripts.list(vid), source, vid);
      final fetched = await transcripts.fetch(track);
      cues = _sorted([for (final c in fetched) Cue(c.start, c.dur, clean(c.text))]);
    } catch (e) {
      Log.warning('Legendas de $vid: $e');
      _setStatus(job, friendlyError(e), error: true);
      return;
    }
    if (!_alive(job)) return;
    if (cues.every((c) => c.text.isEmpty)) {
      _setStatus(job, 'A legenda deste vídeo veio vazia.', error: true);
      return;
    }

    final srcCode = langFamily(track.languageCode);
    final tgt = targetFor(track.languageCode);
    final m = SubtitleMeta(
      cues: cues,
      sourceName: languageName(track),
      sourceCode: track.languageCode,
      generated: track.isGenerated,
      target: tgt,
      targetName: targetName(tgt),
    );
    Log.info('Vídeo $vid: ${cues.length} falas em ${track.languageCode} '
        '(${track.isGenerated ? 'auto' : 'manual'}) -> $tgt');
    _onTranscript(job, m);
    _setStatus(job, 'Traduzindo para ${m.targetName}…');

    // 2) tradução em lotes, começando pelo trecho onde o vídeo está
    final items = [
      for (var i = 0; i < cues.length; i++)
        if (cues[i].text.isNotEmpty) (i, cues[i].text),
    ];
    final chunks = makeChunks(items);
    final translator = Translator(
      translation,
      srcCode == 'en' || srcCode == 'pt' ? srcCode : 'auto',
      tgt,
      sourceLang: track.languageCode,
    );
    final collected = <(int, String)>[];
    var pending = [for (var i = 0; i < chunks.length; i++) i];
    var lastError = '';

    for (final wait in [0, ...retryWaits]) {
      if (pending.isEmpty) break;
      if (wait > 0) {
        _setStatus(job, '$lastError — tentando de novo em $wait s…', error: true);
        if (!await _sleep(job, Duration(seconds: wait))) return;
      }
      var failed = <int>[];
      var streak = 0;
      while (pending.isNotEmpty) {
        if (!_alive(job)) return;
        final cid = _nextChunk(pending, chunks);
        pending.remove(cid);
        final chunk = chunks[cid];
        final List<String> out;
        try {
          out = await translator.translate([for (final (_, t) in chunk) t]);
        } on RateLimited catch (e) {
          // o Google bloqueou e a reserva não deu conta: espera e retoma sozinho
          pending.add(cid);
          if (!await _waitBlock(job, e.until, e.fallback)) return;
          continue;
        } on TranslateError catch (e) {
          lastError = e.message;
          failed.add(cid);
          streak++;
          _setStatus(job, 'Falha ao traduzir: $e', error: true);
          if (streak >= 2) {
            // serviço fora do ar: espera um pouco antes de insistir
            failed = [...failed, ...pending];
            pending = [];
          }
          continue;
        }
        streak = 0;
        final pairs = [
          for (var k = 0; k < math.min(chunk.length, out.length); k++) (chunk[k].$1, out[k]),
        ];
        collected.addAll(pairs);
        if (_alive(job)) {
          _onTranslations(job, pairs);
          if (translator.last == 'MyMemory') {
            // a interface acabou de pôr "Traduzindo… N%"
            final why = translator.googleBlocked ? 'o Google bloqueou temporariamente' : 'o Google falhou';
            _setStatus(
              job,
              'Traduzindo pelo MyMemory (reserva, até ${thousands(myMemoryDailyChars)} caracteres '
              'por dia), porque $why… ${(100 * collected.length / items.length).round()}%',
            );
          }
        }
      }
      pending = failed;
    }

    if (!_alive(job)) return;
    if (pending.isNotEmpty) {
      final missing = pending.fold<int>(0, (n, c) => n + chunks[c].length);
      final msg = '$missing falas ficaram sem tradução ($lastError). '
          'Clique em Abrir para tentar de novo. Detalhes em Diagnóstico › Registro';
      Log.warning(msg);
      _setStatus(job, msg, error: true);
      return;
    }
    final engines = (translator.used.toList()..sort()).join(' + ');
    final done = '${m.sourceName} → ${m.targetName} ✓ (${engines.isEmpty ? '—' : engines})';
    cache.put(vid, source, CachedSubtitles(m, collected, done));
    _setStatus(job, done);
  }

  /// As falas em ordem de início (o YouTube já manda assim; isto só garante,
  /// mantendo a ordem original nos empates).
  static List<Cue> _sorted(List<Cue> cues) {
    for (var i = 1; i < cues.length; i++) {
      if (cues[i].start < cues[i - 1].start) {
        final indexed = [for (var k = 0; k < cues.length; k++) (k, cues[k])]
          ..sort((a, b) {
            final c = a.$2.start.compareTo(b.$2.start);
            return c != 0 ? c : a.$1 - b.$1;
          });
        return [for (final (_, c) in indexed) c];
      }
    }
    return cues;
  }
}
