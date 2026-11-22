/// "Formar frases": traduzir frases das legendas do banco montando a tradução com fichas, como no
/// Duolingo, pela ordem das palavras que mais se repetem nas legendas (a API analisa as falas e
/// manda as frases já nessa ordem).
///
/// As frases vêm em lições de [QuizSession.lessonSize]; a frase errada volta uma vez no fim da
/// lição. Onde o quiz parou fica nas preferências (na API), e a próxima lição começa dali.
library;

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../data/prefs.dart';

class QuizSession extends ChangeNotifier {
  QuizSession({required this.api, required this.prefs, this.lessonSize = 10});

  final ApiClient api;
  final Prefs prefs;
  final int lessonSize;

  bool loading = false;

  /// Problema para mostrar no lugar da frase ("" = nenhum).
  String error = '';

  /// Quantas frases o quiz tem ao todo.
  int total = 0;

  /// Todas as frases do quiz já foram feitas.
  bool completedAll = false;

  List<QuizItem> _lesson = []; // a fila da lição: as erradas voltam no fim
  int _index = 0;
  final Set<int> _retried = {};
  bool _saveProgress = true; // a lição veio de onde o quiz parou (não de uma palavra escolhida)

  /// Quantas lições já começaram (a tela usa para saber que a frase mudou).
  int lessons = 0;

  /// Em que frase da lição está (de 0).
  int get step => _index;

  /// As fichas escolhidas (índices em [QuizItem.tiles]), na ordem.
  final List<int> picked = [];

  /// Resultado da frase atual: null enquanto não conferiu.
  bool? correct;

  /// Acertos e respostas nesta lição.
  int right = 0;
  int answered = 0;

  QuizItem? get current => _index < _lesson.length ? _lesson[_index] : null;

  /// A lição acabou (todas as frases, e as que voltaram, respondidas).
  bool get finished => !loading && error.isEmpty && _lesson.isNotEmpty && _index >= _lesson.length;

  /// Quanto da lição já foi (0 a 1), para a barra de progresso.
  double get progress => _lesson.isEmpty ? 0 : (_index + (correct == null ? 0 : 1)) / _lesson.length;

  List<String> get chosenWords {
    final item = current;
    return item == null ? const [] : [for (final i in picked) item.tiles[i]];
  }

  bool get canCheck => correct == null && picked.isNotEmpty;

  /// Começa uma lição em [at] (de 0; praticar uma palavra escolhida, sem mudar onde o quiz parou);
  /// sem ele, onde o quiz parou.
  Future<void> start({int? at}) async {
    lessons++;
    _saveProgress = at == null;
    loading = true;
    error = '';
    completedAll = false;
    notifyListeners();
    final from = at ?? prefs.quizPos;
    try {
      final batch = await api.quiz(start: from, count: lessonSize);
      total = batch.total;
      _lesson = List.of(batch.items);
      if (_lesson.isEmpty) {
        if (batch.total > 0 && from >= batch.total) {
          completedAll = true;
        } else {
          error = batch.dbMessage.isNotEmpty
              ? batch.dbMessage
              : 'Ainda não há frases traduzidas no banco: abra alguns vídeos primeiro.';
        }
      }
    } on ApiFailure catch (e) {
      error = e.message;
      _lesson = [];
    }
    _index = 0;
    _retried.clear();
    picked.clear();
    correct = null;
    right = 0;
    answered = 0;
    loading = false;
    notifyListeners();
  }

  void pick(int tile) {
    final item = current;
    if (item == null || correct != null || picked.contains(tile) || tile < 0 || tile >= item.tiles.length) return;
    picked.add(tile);
    notifyListeners();
  }

  void unpick(int tile) {
    if (correct != null || !picked.remove(tile)) return;
    notifyListeners();
  }

  /// Confere a resposta (maiúsculas não contam). Acertou: o quiz passa a começar depois desta
  /// frase. Errou: ela volta no fim da lição (uma vez).
  void check() {
    final item = current;
    if (item == null || !canCheck) return;
    final got = [for (final w in chosenWords) w.toLowerCase()].join(' ');
    final want = [for (final w in item.answer) w.toLowerCase()].join(' ');
    final ok = got == want;
    correct = ok;
    answered++;
    if (ok) {
      right++;
      if (_saveProgress && item.position > prefs.quizPos) prefs.quizPos = item.position;
    } else if (_retried.add(item.position)) {
      _lesson.add(item);
    }
    notifyListeners();
  }

  /// Vai para a próxima frase (depois de conferir).
  void next() {
    if (correct == null) return;
    _index++;
    picked.clear();
    correct = null;
    notifyListeners();
  }
}
