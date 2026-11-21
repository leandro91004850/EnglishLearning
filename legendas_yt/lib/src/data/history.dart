import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/subtitles.dart';
import '../youtube/video_id.dart';
import 'banco.dart';
import 'json_file.dart';

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

/// Lista de vídeos (Recentes), sem limite: com o banco de dados, todos os vídeos
/// guardados lá (os que estavam fora da lista entram no fim dela a cada leitura).
/// Link novo entra no topo; vídeo aberto pela própria lista fica no lugar, para
/// que, quando ele termina, o app siga para o de baixo. Tocar e segurar um vídeo
/// e arrastar muda a ordem ([reorder]). `at` diz quando cada um foi aberto pela
/// última vez.
///
/// Com o banco de dados ([attach]), a lista vai para o banco numa fila à parte
/// (o `History` do app.py do legendas-yt): inteira quando ela muda (vídeo novo,
/// ordem, remoção); só a linha do vídeo quando muda apenas onde ele parou ou o
/// título. O arquivo historico.json fica como cópia no aparelho, para o app
/// lembrar dos vídeos mesmo sem conexão. Ao ler a lista do banco ([loadFromDb]):
/// se o aparelho estava em dia com o banco, vale a lista do banco (pode ter
/// mudado no app do computador), e os vídeos mexidos nesta sessão antes disso
/// ficam no topo; se o aparelho tinha mudanças que não chegaram ao banco, a lista
/// do aparelho fica por cima e os outros vídeos do banco vêm depois.
class History extends ChangeNotifier {
  History(this.file, {DateTime Function()? now}) : _now = now ?? DateTime.now {
    _items = _read();
    _synced = readJson<Map<String, dynamic>>(_syncFile, const {})['sincronizado'] == true;
    _syncedAtStart = _synced;
  }

  final File file;
  final DateTime Function() _now;
  late List<HistoryItem> _items;
  bool _dirty = false;
  DateTime _savedAt = DateTime.fromMillisecondsSinceEpoch(0);

  // ---- banco de dados ----
  Banco? _db;
  bool _dbLoaded = false;

  /// A lista do aparelho é a mesma do banco (gravado em historico-banco.json).
  late bool _synced;
  late bool _syncedAtStart;

  /// Vídeos mexidos nesta sessão antes de ler a lista do banco.
  final Set<String> _touched = {};

  /// A ordem mudou ou um vídeo saiu antes de ler a lista do banco.
  bool _listChanged = false;

  /// A lista mudou (vídeo novo, ordem, remoção): vai inteira para o banco.
  bool _dbWhole = false;

  /// Só onde estes vídeos pararam ou o título deles mudou: vão só as linhas deles.
  final Set<String> _dbRows = {};
  bool _dbQueued = false;
  DateTime _dbSavedAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _dbDirty => _dbWhole || _dbRows.isNotEmpty;

  File get _syncFile => File('${file.parent.path}/historico-banco.json');

  List<HistoryItem> _read() {
    final data = readJson<List<dynamic>>(file, const []);
    final ok = <HistoryItem>[];
    for (final x in data) {
      if (x is Map<String, dynamic> && isVideoId(x['id'] is String ? x['id'] as String : null)) {
        ok.add(HistoryItem.fromJson(x));
      }
    }
    return ok;
  }

  /// Os vídeos, na ordem em que aparecem.
  List<HistoryItem> get items => List.unmodifiable(_items);

  /// O × da lista. Com o banco de dados não há ×: a lista tem todos os vídeos de
  /// lá, e um vídeo tirado dela voltaria na próxima leitura do banco.
  bool get canRemove => !(_db?.configured ?? false);

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

  /// [whole]: a lista mudou, e não só onde o vídeo [id] parou ou o título dele.
  void _changed({String? id, bool whole = true}) {
    _dirty = true;
    if (whole) {
      _dbWhole = true;
    } else if (id != null) {
      _dbRows.add(id);
    }
    if (!_dbLoaded) {
      if (id != null) {
        _touched.add(id);
      } else {
        _listChanged = true;
      }
    }
    _setSynced(false);
  }

  void _setSynced(bool value) {
    if (_synced == value) return;
    _synced = value;
    writeJson(_syncFile, {'sincronizado': value});
  }

  /// Vídeo aberto agora. Sem [keepPlace] (link colado), vai para o topo; com
  /// [keepPlace] (aberto pela lista, ou o mesmo vídeo de novo), fica onde está e,
  /// se tinha saído da lista, não volta. [restoring]: o app reabriu o último
  /// vídeo ao iniciar (não conta como mudança da lista). Devolve true se ainda
  /// não tem título.
  bool opened(String videoId, String source, {bool keepPlace = false, bool restoring = false}) {
    var item = find(videoId);
    if (item == null && keepPlace) return false;
    final needTitle = (item?.title ?? '').isEmpty;
    if (restoring && item != null) return needTitle;
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
    _changed(id: videoId);
    save();
    notifyListeners();
    return needTitle;
  }

  /// Tira o vídeo da lista. Devolve true se ele estava lá.
  bool remove(String videoId) {
    final before = _items.length;
    _items.removeWhere((x) => x.id == videoId);
    if (_items.length == before) return false;
    _changed();
    save();
    notifyListeners();
    return true;
  }

  /// Sobe (delta < 0) ou desce (delta > 0) o vídeo na lista, sem mudar o `at`.
  /// Devolve true se ele mudou de lugar.
  bool move(String videoId, int delta) {
    final i = indexOf(videoId);
    return i >= 0 && reorder(i, i + delta);
  }

  /// Leva o vídeo da posição [from] para a posição [to] (arrastando na lista),
  /// sem mudar o `at`. Devolve true se ele mudou de lugar.
  bool reorder(int from, int to) {
    if (from < 0 || from >= _items.length) return false;
    final j = to.clamp(0, _items.length - 1);
    if (j == from) return false;
    _items.insert(j, _items.removeAt(from));
    _changed();
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
    _changed(id: videoId, whole: false);
    notifyListeners();
  }

  /// Grava se algo mudou (no aparelho e, com o banco, na fila do banco); com
  /// `force: false`, no máximo a cada [historySaveEvery].
  void save({bool force = true}) {
    _saveLocal(force: force);
    _queueDb(force: force);
  }

  void _saveLocal({bool force = true}) {
    if (!_dirty) return;
    if (!force && _now().difference(_savedAt) < historySaveEvery) return;
    if (writeJson(file, [for (final x in _items) x.toJson()])) {
      _dirty = false;
      _savedAt = _now();
    }
  }

  // ---- banco de dados ----

  void attach(Banco db) => _db = db;

  /// Lê a lista do banco e junta com a do aparelho (veja a explicação da classe).
  /// Antes, os vídeos do banco que estão fora da lista entram no fim dela
  /// ([Banco.addMissingVideos]): a lista tem todos. Devolve false se o banco não
  /// respondeu.
  Future<bool> loadFromDb() async {
    final db = _db;
    if (db == null || !db.configured) return false;
    if (_dbLoaded) return true;
    await db.addMissingVideos();
    final saved = await db.loadRecent();
    if (saved == null) return false;
    if (_dbLoaded) return true; // outra chamada leu enquanto esta esperava
    final fromDb = <HistoryItem>[];
    for (final m in saved) {
      if (isVideoId(m['id'] is String ? m['id'] as String : null)) {
        fromDb.add(HistoryItem.fromJson(Map<String, dynamic>.from(m)));
      }
    }
    final keep = _syncedAtStart && !_listChanged
        ? [for (final x in _items) if (_touched.contains(x.id)) x]
        : List.of(_items);
    final ids = {for (final x in keep) x.id};
    _items = [...keep, ...fromDb.where((x) => !ids.contains(x.id))];
    _dbLoaded = true;
    _touched.clear();
    _listChanged = false;
    if (keep.isEmpty) {
      _setSynced(true);
    } else {
      _dbWhole = true;
    }
    _dirty = true;
    _saveLocal();
    notifyListeners();
    return true;
  }

  void _queueDb({required bool force}) {
    final db = _db;
    if (db == null || !db.configured || !_dbDirty || _dbQueued) return;
    if (!force && _now().difference(_dbSavedAt) < historySaveEvery) return;
    _dbQueued = true;
    if (!db.submit(_writeDb)) _dbQueued = false;
  }

  /// Na fila do banco. A lista mudou: grava a lista inteira numa transação;
  /// senão, só as linhas dos vídeos que mudaram. Se o banco estava fora do ar na
  /// abertura, antes junta a lista que está lá.
  Future<void> _writeDb() async {
    _dbQueued = false;
    final db = _db;
    if (db == null) return;
    if (!_dbLoaded && !await loadFromDb()) return; // ainda fora do ar: as mudanças continuam marcadas
    final whole = _dbWhole;
    final rows = Set.of(_dbRows);
    final items = [for (final x in _items) if (whole || rows.contains(x.id)) x.toJson()];
    _dbWhole = false;
    _dbRows.clear();
    _dbSavedAt = _now();
    if (await (whole ? db.saveRecent(items) : db.updateRecent(items))) {
      if (!_dbDirty) _setSynced(true);
    } else {
      _dbWhole = _dbWhole || whole;
      _dbRows.addAll(rows);
    }
  }

  /// Os dados de acesso do banco mudaram: a lista do aparelho vai por cima da
  /// lista do banco novo na próxima leitura.
  void dbReset() {
    _dbLoaded = false;
    _syncedAtStart = false;
    _touched.clear();
    _listChanged = false;
    _dbWhole = true;
    _setSynced(false);
    notifyListeners(); // o × aparece ou some ([canRemove])
  }
}

