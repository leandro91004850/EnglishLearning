import 'dart:io';

import 'package:flutter/foundation.dart';

import 'banco.dart';
import 'json_file.dart';

/// O que mostrar sobre o vídeo.
enum ShowMode {
  both('both', 'Ambas'),
  translation('tr', 'Tradução'),
  original('orig', 'Original');

  const ShowMode(this.code, this.label);
  final String code;
  final String label;

  static ShowMode parse(Object? code) =>
      values.firstWhere((m) => m.code == code, orElse: () => ShowMode.both);
}

/// Preferências da interface: `{subSize: int, show: "both" | "tr" | "orig"}`
/// (o `preferencias.json` do app.py).
class Prefs extends ChangeNotifier {
  Prefs(this.file) {
    final data = readJson<Map<String, dynamic>>(file, const {});
    for (final key in keys) {
      final value = data[key];
      if (value is int || value is String) _data[key] = value as Object;
    }
  }

  static const List<String> keys = ['subSize', 'show'];
  static const int minSubSize = 14, maxSubSize = 48, defaultSubSize = 24;

  final File file;
  final Map<String, Object> _data = {};

  Map<String, Object> get all => Map.unmodifiable(_data);

  /// Tamanho da legenda (pontos, para um vídeo de 720 de largura; cresce e
  /// diminui com o vídeo).
  int get subSize {
    final v = _data['subSize'];
    return v is int ? v.clamp(minSubSize, maxSubSize) : defaultSubSize;
  }

  ShowMode get show => ShowMode.parse(_data['show']);

  set subSize(int value) => set('subSize', value.clamp(minSubSize, maxSubSize));
  set show(ShowMode value) => set('show', value.code);

  void set(String key, Object value) {
    if (!keys.contains(key) || value is bool || (value is! int && value is! String)) return;
    if (_data[key] == value) return;
    _data[key] = value;
    _changedHere.add(key);
    writeJson(file, _data);
    final db = _db;
    db?.submit(() => db.savePref(key, value));
    notifyListeners();
  }

  // ---- banco de dados (tabela preferencias, a mesma do app.py) ----

  Banco? _db;
  final Set<String> _changedHere = {}; // mudadas nesta sessão antes de ler o banco

  void attach(Banco db) => _db = db;

  /// Lê as preferências do banco: valem as de lá, menos as mudadas nesta sessão;
  /// as que o banco ainda não tem vão do aparelho para o banco.
  Future<void> loadFromDb() async {
    final db = _db;
    if (db == null || !db.configured) return;
    final saved = await db.loadPrefs();
    if (saved == null) return;
    var changed = false;
    for (final key in keys) {
      final value = saved[key];
      if (!saved.containsKey(key)) {
        final mine = _data[key];
        if (mine != null) db.submit(() => db.savePref(key, mine));
      } else if (!_changedHere.contains(key) && (value is int || value is String) && _data[key] != value) {
        _data[key] = value!;
        changed = true;
      }
    }
    _changedHere.clear();
    if (changed) {
      writeJson(file, _data);
      notifyListeners();
    }
  }

  void dbReset() => _changedHere.clear();
}
