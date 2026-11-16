import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/subtitles.dart';
import '../youtube/video_id.dart';
import 'json_file.dart';

const int historyLimit = 30;
const Duration historySaveEvery = Duration(seconds: 15); // entre gravações da posição do vídeo

/// Um vídeo da lista de recentes. Mesmo formato do `historico.json` do app.py:
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

  Map<String, Object> toJson() => {
        'id': id,
        'url': url,
        'source': source,
        'at': at,
        if (title.isNotEmpty) 'title': title,
        if (author.isNotEmpty) 'author': author,
        if (pos > 0) 'pos': pos,
        if (dur > 0) 'dur': dur,
      };
}

/// Lista de vídeos recentes.
/// Link novo entra no topo; vídeo aberto pela própria lista fica no lugar, para
/// que, quando ele termina, o app siga para o de baixo. As setas da lista sobem
/// ou descem um vídeo ([move]). `at` diz quando cada um foi aberto pela última vez.
class History extends ChangeNotifier {
  History(this.file, {this.limit = historyLimit, DateTime Function()? now})
      : _now = now ?? DateTime.now {
    _items = _read();
  }

  final File file;
  final int limit;
  final DateTime Function() _now;
  late List<HistoryItem> _items;
  bool _dirty = false;
  DateTime _savedAt = DateTime.fromMillisecondsSinceEpoch(0);

  List<HistoryItem> _read() {
    final data = readJson<List<dynamic>>(file, const []);
    final ok = <HistoryItem>[];
    for (final x in data) {
      if (x is Map<String, dynamic> && isVideoId(x['id'] is String ? x['id'] as String : null)) {
        ok.add(HistoryItem.fromJson(x));
      }
    }
    return ok.take(limit).toList();
  }

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

  /// Vídeo aberto agora. Sem [keepPlace] (link colado), vai para o topo; com
  /// [keepPlace] (aberto pela lista, ou o mesmo vídeo de novo), fica onde está e,
  /// se tinha saído da lista, não volta. Devolve true se ainda não tem título.
  bool opened(String videoId, String source, {bool keepPlace = false}) {
    var item = find(videoId);
    if (item == null && keepPlace) return false;
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
    if (_items.length > limit) _items.removeRange(limit, _items.length);
    _dirty = true;
    final needTitle = item.title.isEmpty;
    save();
    notifyListeners();
    return needTitle;
  }

  /// Tira o vídeo da lista. Devolve true se ele estava lá.
  bool remove(String videoId) {
    final before = _items.length;
    _items.removeWhere((x) => x.id == videoId);
    if (_items.length == before) return false;
    _dirty = true;
    save();
    notifyListeners();
    return true;
  }

  /// Sobe (delta < 0) ou desce (delta > 0) o vídeo na lista, sem mudar o `at`.
  /// Devolve true se ele mudou de lugar.
  bool move(String videoId, int delta) {
    final i = indexOf(videoId);
    if (i < 0) return false;
    final j = (i + delta).clamp(0, _items.length - 1);
    if (j == i) return false;
    _items.insert(j, _items.removeAt(i));
    _dirty = true;
    save();
    notifyListeners();
    return true;
  }

  /// Atualiza título ou posição de um vídeo, sem mudar a ordem.
  void update(String videoId, {String? title, String? author, double? pos, double? dur}) {
    final item = find(videoId);
    if (item == null) return;
    if (title != null) item.title = title;
    if (author != null) item.author = author;
    if (pos != null) item.pos = pos;
    if (dur != null) item.dur = dur;
    _dirty = true;
    notifyListeners();
  }

  /// Grava se algo mudou; com `force: false`, no máximo a cada [historySaveEvery].
  void save({bool force = true}) {
    if (!_dirty) return;
    if (!force && _now().difference(_savedAt) < historySaveEvery) return;
    if (writeJson(file, [for (final x in _items) x.toJson()])) {
      _dirty = false;
      _savedAt = _now();
    }
  }
}
