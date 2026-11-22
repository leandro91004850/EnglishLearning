import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../core/log.dart';

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

/// Preferências da interface: `{subSize: int, show: "both" | "tr" | "orig", quizPos: int}`. Ficam na API
/// (tabela preferencias do banco, a mesma do app.py); o app lê ao abrir ([load]) e manda cada
/// mudança na hora.
class Prefs extends ChangeNotifier {
  Prefs(this.api);

  final ApiClient api;

  static const List<String> keys = ['subSize', 'show', 'quizPos'];
  static const int minSubSize = 14, maxSubSize = 48, defaultSubSize = 24;

  final Map<String, Object> _data = {};
  final Set<String> _changedHere = {}; // mudadas nesta sessão antes de ler a API

  Map<String, Object> get all => Map.unmodifiable(_data);

  /// Tamanho da legenda (pontos, para um vídeo de 720 de largura; cresce e diminui com o vídeo).
  int get subSize {
    final v = _data['subSize'];
    return v is int ? v.clamp(minSubSize, maxSubSize) : defaultSubSize;
  }

  ShowMode get show => ShowMode.parse(_data['show']);

  /// Onde o quiz "Formar frases" parou: a próxima frase (de 0).
  int get quizPos {
    final v = _data['quizPos'];
    return v is int && v > 0 ? v : 0;
  }

  set subSize(int value) => set('subSize', value.clamp(minSubSize, maxSubSize));
  set show(ShowMode value) => set('show', value.code);
  set quizPos(int value) => set('quizPos', value < 0 ? 0 : value);

  void set(String key, Object value) {
    if (!keys.contains(key) || value is bool || (value is! int && value is! String)) return;
    if (_data[key] == value) return;
    _data[key] = value;
    _changedHere.add(key);
    notifyListeners();
    unawaited(_send(key, value));
  }

  Future<void> _send(String key, Object value) async {
    try {
      await api.savePrefs({key: value});
    } on ApiFailure catch (e) {
      Log.warning('Preferência $key: ${e.message}');
    }
  }

  /// Lê as preferências da API: valem as de lá, menos as mudadas nesta sessão.
  Future<void> load() async {
    final Map<String, dynamic> saved;
    try {
      saved = await api.prefs();
    } on ApiFailure catch (e) {
      Log.warning('Preferências: ${e.message}');
      return;
    }
    var changed = false;
    for (final key in keys) {
      final value = saved[key];
      if (!_changedHere.contains(key) && (value is int || value is String) && _data[key] != value) {
        _data[key] = value as Object;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }
}
