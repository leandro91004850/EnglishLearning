/// O vídeo aberto e a legenda dele com a tradução, que vêm da API.
///
/// Abrir um vídeo ([load]) começa um "job" novo: o app abre o vídeo na API e pergunta pelo
/// andamento até a legenda ficar pronta. A API busca a legenda (no banco ou no YouTube) e traduz
/// em lotes, começando pelo trecho onde o vídeo está ([focus]). O job antigo para sozinho na
/// próxima vez que confere [_alive].
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../core/cue.dart';
import '../core/log.dart';
import '../core/subtitles.dart';
import '../data/history.dart';
import '../youtube/video_id.dart';

class LoadResult {
  const LoadResult.ok(String this.videoId) : error = null;
  const LoadResult.error(String this.error) : videoId = null;
  final String? videoId;
  final String? error;
  bool get ok => videoId != null;
}

class SubtitleSession extends ChangeNotifier {
  SubtitleSession({required this.api, required this.history, this.pollEvery = const Duration(milliseconds: 600)});

  final ApiClient api;
  final History history;

  /// Intervalo entre as perguntas à API enquanto a legenda é preparada.
  final Duration pollEvery;

  int _job = 0;
  String? _apiJob; // id da legenda na API
  int _focus = 0;
  int _focusSent = -1;
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

  /// A API ainda está buscando a legenda ou traduzindo.
  bool busy = false;

  List<Cue> get cues => meta?.cues ?? const [];
  int get job => _job;

  // ---- chamados pela interface ----

  /// Abre o vídeo e começa a buscar a legenda. [keepPlace]: o vídeo foi aberto pela lista de
  /// recentes e fica no lugar dele. [restoring]: o app reabriu o último vídeo ao iniciar.
  LoadResult load(String url, {String source = 'auto', bool keepPlace = false, bool restoring = false}) {
    final vid = extractVideoId(url);
    if (vid == null) return const LoadResult.error('Link do YouTube inválido.');
    source = normalizeSource(source);
    final job = ++_job;
    // o mesmo vídeo de novo (trocou o idioma, nova tentativa) também não muda de lugar
    keepPlace = keepPlace || vid == videoId;

    videoId = vid;
    this.source = source;
    meta = null;
    translations = const [];
    translated = 0;
    toTranslate = 0;
    status = '';
    statusError = false;
    busy = true;
    _apiJob = null;
    _focus = 0;
    _focusSent = -1;
    notifyListeners();

    history.opened(vid, source, keepPlace: keepPlace, restoring: restoring);
    unawaited(_run(job, vid, source, keepPlace, restoring));
    return LoadResult.ok(vid);
  }

  /// A interface avisa onde o vídeo está, para a API traduzir esse trecho primeiro.
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

  Future<void> _run(int job, String vid, String source, bool keepPlace, bool restoring) async {
    try {
      final id = await api.open(vid, source: source, keepPlace: keepPlace, restoring: restoring);
      if (!_alive(job)) return;
      _apiJob = id;
      var since = 0;
      while (_alive(job)) {
        final state = await api.job(id, since: since, cues: meta == null);
        if (!_alive(job)) return;
        final m = state.meta;
        if (m != null && meta == null) _onTranscript(m);
        if (meta != null) {
          _onTranslations(state.translations);
          since = state.total;
        }
        if (state.title.isNotEmpty) history.update(vid, title: state.title, author: state.author);
        status = state.message;
        statusError = state.error;
        notifyListeners();
        if (state.finished) return;
        await _sendFocus();
        await Future<void>.delayed(pollEvery);
      }
    } on ApiFailure catch (e) {
      Log.warning('Legenda de $vid: ${e.message}');
      if (_alive(job)) {
        status = e.message;
        statusError = true;
      }
    } finally {
      if (_alive(job)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _sendFocus() async {
    final id = _apiJob;
    if (id == null || _focus == _focusSent) return;
    _focusSent = _focus;
    try {
      await api.focus(id, _focus);
    } on ApiFailure {
      // só muda a ordem da tradução: sem ele, a legenda continua vindo
    }
  }

  void _onTranscript(SubtitleMeta m) {
    meta = m;
    translations = List<String?>.filled(m.cues.length, null);
    translated = 0;
    toTranslate = m.cues.where((c) => c.text.isNotEmpty).length;
  }

  void _onTranslations(List<(int, String)> pairs) {
    for (final (i, text) in pairs) {
      if (i < 0 || i >= translations.length) continue;
      if (translations[i] == null) translated++;
      translations[i] = text;
    }
  }
}
