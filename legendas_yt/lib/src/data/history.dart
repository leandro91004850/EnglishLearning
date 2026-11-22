import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../core/log.dart';
import '../core/subtitles.dart';
import '../youtube/video_id.dart';

const Duration historySaveEvery = Duration(seconds: 15); // entre os envios da posição do vídeo

/// Um vídeo da lista de recentes. Mesmo formato do `historico.json` do app.py e da API:
/// `{id, url, source, at, title, author, pos, dur}`.
class HistoryItem {
  HistoryItem({
    required this.id,
    this.url = '',
    this.source = 'auto',
    this.at = 0,
    this.title = '',
    this.author = '',
    this.pos = 0,
    this.dur = 0,
  });

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    String str(Object? v) => v is String ? v : '';
    double number(Object? v) => v is num && v.isFinite ? v.toDouble() : 0;
    return HistoryItem(
      id: json['id'] as String,
      url: str(json['url']),
      source: normalizeSource(json['source'] as String?),
      at: number(json['at']).toInt(),
      title: str(json['title']),
      author: str(json['author']),
      pos: number(json['pos']),
      dur: number(json['dur']),
    );
  }

  final String id;
  String url;
  String source;

  /// Quando foi aberto pela última vez (segundos desde 1970).
  int at;
  String title;
  String author;

  /// Onde o vídeo parou e quanto ele dura (segundos).
  double pos;
  double dur;

  String get link => url.isNotEmpty ? url : watchUrlFor(id);

  double get progress => dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0;

  /// Onde retomar: a posição salva, menos se estiver bem no começo ou no fim.
  double get resumeAt => pos > 5 && (dur <= 0 || pos < dur - 10) ? pos : 0;
}

/// A lista de vídeos (Recentes). Vem da API: todos os vídeos do banco de dados, na ordem da
/// lista e com onde cada um parou. O app guarda só uma cópia na memória, que muda na hora quando
/// um vídeo é aberto (a API faz o mesmo no banco), arrastado ([reorder], a nova ordem vai para a
/// API) ou quando ele toca ([update]; onde ele parou vai para a API em [save]).
/// Link novo entra no topo; vídeo aberto pela própria lista fica no lugar, para que, quando ele
/// termina, o app siga para o de baixo.
class History extends ChangeNotifier {
  History(this.api, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final ApiClient api;
  final DateTime Function() _now;
  List<HistoryItem> _items = [];

  /// A lista já veio da API pelo menos uma vez.
  bool loaded = false;

  final Map<String, HistoryItem> _positions = {}; // onde o vídeo parou, ainda não enviado
  DateTime _sentAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _sending = Future.value();
  Future<void> _ordering = Future.value();
  List<String> _sentOrder = const []; // a ordem que a API já tem

  /// Os vídeos, na ordem em que aparecem.
  List<HistoryItem> get items => List.unmodifiable(_items);

  bool get isEmpty => _items.isEmpty;

  HistoryItem? find(String videoId) {
    for (final x in _items) {
      if (x.id == videoId) return x;
    }
    return null;
  }

  int indexOf(String videoId) => _items.indexWhere((x) => x.id == videoId);

  /// O último vídeo assistido (o que o app reabre ao iniciar).
  HistoryItem? get latest =>
      _items.isEmpty ? null : _items.reduce((a, b) => b.at > a.at ? b : a);

  /// Lê a lista da API. Devolve o problema ("" = tudo certo): a API fora do ar, ou o banco de
  /// dados dela com problema (aí a lista vem vazia).
  Future<String> load() async {
    try {
      final list = await api.recent();
      _items = [
        for (final m in list.videos)
          if (isVideoId(m['id'] is String ? m['id'] as String : null)) HistoryItem.fromJson(m),
      ];
      _sentOrder = [for (final x in _items) x.id];
      loaded = true;
      notifyListeners();
      return list.dbMessage;
    } on ApiFailure catch (e) {
      Log.warning('Lista de vídeos: ${e.message}');
      return e.message;
    }
  }

  /// Vídeo aberto agora. Sem [keepPlace] (link colado), vai para o topo; com [keepPlace] (aberto
  /// pela lista, ou o mesmo vídeo de novo), fica onde está. [restoring]: o app reabriu o último
  /// vídeo ao iniciar (a lista não muda).
  void opened(String videoId, String source, {bool keepPlace = false, bool restoring = false}) {
    if (restoring) return;
    var item = find(videoId);
    if (item == null && keepPlace) return;
    if (item == null) {
      item = HistoryItem(id: videoId);
      _items.insert(0, item);
    } else if (!keepPlace) {
      _items.remove(item);
      _items.insert(0, item);
    }
    item
      ..url = watchUrlFor(videoId)
      ..source = source
      ..at = _now().millisecondsSinceEpoch ~/ 1000;
    notifyListeners();
  }

  /// Sobe (delta < 0) ou desce (delta > 0) o vídeo na lista. Devolve true se ele mudou de lugar.
  bool move(String videoId, int delta) {
    final i = indexOf(videoId);
    return i >= 0 && reorder(i, i + delta);
  }

  /// Leva o vídeo da posição [from] para a posição [to] (arrastando na lista), sem mudar o `at`,
  /// e manda a nova ordem para a API. Devolve true se ele mudou de lugar.
  bool reorder(int from, int to) {
    if (from < 0 || from >= _items.length) return false;
    final j = to.clamp(0, _items.length - 1);
    if (j == from) return false;
    _items.insert(j, _items.removeAt(from));
    notifyListeners();
    // uma de cada vez, sempre com a ordem mais nova
    _ordering = _ordering.then((_) => _sendOrder());
    return true;
  }

  Future<void> _sendOrder() async {
    final ids = [for (final x in _items) x.id];
    if (listEquals(ids, _sentOrder)) return; // outro envio já levou esta ordem
    try {
      await api.reorder(ids);
      _sentOrder = ids;
    } on ApiFailure catch (e) {
      Log.warning('Nova ordem da lista: ${e.message}');
    }
  }

  /// Título ou posição de um vídeo, sem mudar a ordem. A posição vai para a API em [save].
  void update(String videoId, {String? title, String? author, double? pos, double? dur}) {
    final item = find(videoId);
    if (item == null) return;
    if (title == item.title && (author == null || author == item.author) && pos == null && dur == null) return;
    if (title != null) item.title = title;
    if (author != null) item.author = author;
    if (pos != null) item.pos = pos;
    if (dur != null) item.dur = dur;
    if (pos != null || dur != null) _positions[videoId] = item;
    notifyListeners();
  }

  /// Manda para a API onde os vídeos pararam; com `force: false`, no máximo a cada
  /// [historySaveEvery]. Volta na hora (o envio segue sozinho; [flush] espera).
  void save({bool force = true}) {
    if (_positions.isEmpty) return;
    if (!force && _now().difference(_sentAt) < historySaveEvery) return;
    _sentAt = _now();
    final batch = List.of(_positions.values);
    _positions.clear();
    _sending = _sending.then((_) => _sendPositions(batch));
  }

  Future<void> _sendPositions(List<HistoryItem> batch) async {
    for (final x in batch) {
      try {
        await api.position(x.id, x.pos, x.dur);
      } on ApiFailure catch (e) {
        Log.warning('Posição de ${x.id}: ${e.message}');
        _positions.putIfAbsent(x.id, () => x); // vai de novo no próximo envio
      }
    }
  }

  /// Manda o que falta e espera (ao fechar o app). False se o tempo acabou antes.
  Future<bool> flush([Duration timeout = const Duration(seconds: 5)]) async {
    save();
    try {
      await Future.wait([_sending, _ordering]).timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }
}
