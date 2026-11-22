/// As lições: exercícios com as frases das legendas do banco, como no Duolingo, pela ordem das
/// palavras que mais se repetem nas legendas (a API analisa as falas e manda as frases já nessa
/// ordem). Cada frase vira, por sorteio, um dos exercícios ([Exercise]): traduzir montando a
/// tradução com fichas ou repetir a frase em voz alta.
///
/// As frases vêm em lições de [QuizSession.lessonSize]; a frase errada volta uma vez no fim da
/// lição. Onde o quiz parou fica nas preferências (na API), e a próxima lição começa dali.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../data/prefs.dart';
import 'pronunciation.dart';
import 'voice_input.dart';

/// Os exercícios das lições.
enum Exercise {
  /// "Traduza esta frase": montar a tradução com as fichas.
  translate,

  /// "Repita esta frase": falar a frase em inglês; o reconhecimento de voz confere a pronúncia.
  speak,
}

class _Card {
  _Card(this.item, this.exercise);

  final QuizItem item;
  Exercise exercise;
}

class QuizSession extends ChangeNotifier {
  QuizSession({
    required this.api,
    required this.prefs,
    this.lessonSize = 10,
    this.voice,
    this.speakShare = defaultSpeakShare,
    Random? random,
  }) : _random = random ?? Random.secure(); // Random() repetia o mesmo sorteio a cada vez que o app abria

  /// A parte das frases que vira exercício de falar.
  static const double defaultSpeakShare = 0.3;

  /// Tentativas de falar a frase antes de ela contar como errada.
  static const int maxTries = 3;

  /// "Não posso falar agora": quanto tempo sem exercícios de falar.
  static const Duration quietFor = Duration(minutes: 15);

  final ApiClient api;
  final Prefs prefs;
  final int lessonSize;

  /// O microfone (sem ele, nenhum exercício de falar).
  final VoiceInput? voice;
  final double speakShare;
  final Random _random;

  bool loading = false;

  /// Problema para mostrar no lugar da frase ("" = nenhum).
  String error = '';

  /// Quantas frases o quiz tem ao todo.
  int total = 0;

  /// Todas as frases do quiz já foram feitas.
  bool completedAll = false;

  List<_Card> _lesson = []; // a fila da lição: as erradas voltam no fim
  int _index = 0;
  final Set<int> _retried = {};
  bool _saveProgress = true; // a lição veio de onde o quiz parou (não de uma palavra escolhida)
  bool _closed = false;

  /// Quantas lições já começaram.
  int lessons = 0;

  /// Muda a cada frase nova na tela (a tela usa para ler a frase uma vez só).
  int turn = 0;

  int? _from; // onde a lição atual começou

  /// Arquivando a frase atual (esperando a API).
  bool archiving = false;

  /// Em que frase da lição está (de 0).
  int get step => _index;

  /// As fichas escolhidas (índices em [QuizItem.tiles]), na ordem.
  final List<int> picked = [];

  /// Resultado da frase atual: null enquanto não respondeu.
  bool? correct;

  /// Acertos e respostas nesta lição.
  int right = 0;
  int answered = 0;

  /// Aviso para mostrar com a frase ("" = nenhum): nada ouvido, tente de novo, sem microfone.
  String note = '';

  // Exercício de falar

  /// Ouvindo agora.
  bool listening = false;

  /// O que está sendo ouvido; depois de uma tentativa, o que foi ouvido.
  String hearing = '';

  /// O volume da voz (0 a 1), para a animação do microfone.
  final ValueNotifier<double> level = ValueNotifier(0);

  /// A conferência da última tentativa de falar.
  SpeechCheck? speech;

  /// Tentativas de falar esta frase.
  int tries = 0;

  _Card? get _card => _index < _lesson.length ? _lesson[_index] : null;

  QuizItem? get current => _card?.item;

  /// O exercício da frase atual.
  Exercise get exercise => _card?.exercise ?? Exercise.translate;

  /// A lição acabou (todas as frases, e as que voltaram, respondidas).
  bool get finished => !loading && error.isEmpty && _lesson.isNotEmpty && _index >= _lesson.length;

  /// Quanto da lição já foi (0 a 1), para a barra de progresso.
  double get progress => _lesson.isEmpty ? 0 : (_index + (correct == null ? 0 : 1)) / _lesson.length;

  List<String> get chosenWords {
    final item = current;
    return item == null ? const [] : [for (final i in picked) item.tiles[i]];
  }

  bool get canCheck => exercise == Exercise.translate && correct == null && picked.isNotEmpty;

  /// Começa uma lição em [at] (de 0; praticar uma palavra escolhida, sem mudar onde o quiz parou);
  /// sem ele, onde o quiz parou.
  Future<void> start({int? at}) async {
    lessons++;
    turn++;
    _from = at;
    _saveProgress = at == null;
    _stopListening();
    loading = true;
    error = '';
    completedAll = false;
    notifyListeners();
    final from = at ?? prefs.quizPos;
    try {
      final batch = await api.quiz(start: from, count: lessonSize);
      total = batch.total;
      _lesson = [for (final item in batch.items) _Card(item, _draw())];
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
    if (_closed) return;
    _index = 0;
    _retried.clear();
    picked.clear();
    correct = null;
    right = 0;
    answered = 0;
    note = '';
    _resetSpeaking();
    loading = false;
    notifyListeners();
  }

  /// O sorteio do exercício de cada frase.
  Exercise _draw() {
    final canSpeak = (voice?.available ?? false) && speakShare > 0;
    return canSpeak && _random.nextDouble() < speakShare ? Exercise.speak : Exercise.translate;
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

  /// Confere a tradução montada (maiúsculas não contam).
  void check() {
    final item = current;
    if (item == null || !canCheck) return;
    final got = [for (final w in chosenWords) w.toLowerCase()].join(' ');
    final want = [for (final w in item.answer) w.toLowerCase()].join(' ');
    _answer(got == want);
  }

  /// Exercício de falar: liga o microfone; quando a pessoa termina de falar, confere a pronúncia.
  Future<void> listen() async {
    final input = voice;
    final card = _card;
    if (input == null || card == null || card.exercise != Exercise.speak || correct != null || listening) return;
    note = '';
    final ok = await input.ready();
    if (_closed) return;
    if (!ok) {
      input.blocked = true;
      _speakingOff(
        'Sem acesso ao microfone ou ao reconhecimento de voz: libere nos Ajustes do aparelho. '
        'Por enquanto, as lições seguem sem falar.',
      );
      return;
    }
    if (_card != card || correct != null || listening) return;
    listening = true;
    hearing = '';
    notifyListeners();
    await input.listen(
      onHeard: (heard) {
        if (_closed || _card != card || !listening) return;
        if (!heard.done) {
          hearing = heard.text;
          notifyListeners();
          return;
        }
        listening = false;
        level.value = 0;
        _judge(card.item, heard.transcripts);
      },
      onError: (message) {
        if (_closed || _card != card || !listening) return;
        listening = false;
        level.value = 0;
        hearing = '';
        note = message;
        notifyListeners();
      },
      onLevel: (value) {
        if (!_closed) level.value = value;
      },
    );
  }

  /// Termina de ouvir e confere o que foi dito.
  Future<void> stopListening() async {
    if (listening) await voice?.stop();
  }

  /// Desliga o microfone sem conferir (por exemplo, para ouvir a frase de novo).
  void cancelListening() {
    if (!listening) return;
    _stopListening();
    notifyListeners();
  }

  void _stopListening() {
    if (listening) unawaited(voice?.cancel());
    listening = false;
    level.value = 0;
  }

  void _judge(QuizItem item, List<String> transcripts) {
    if (transcripts.every((t) => t.trim().isEmpty)) {
      hearing = '';
      note = 'Não ouvi nada. Toque no microfone e fale a frase em inglês.';
      notifyListeners();
      return;
    }
    final check = SpeechCheck.best(item.phrase, transcripts);
    speech = check;
    hearing = check.heard;
    tries++;
    if (check.passed || tries >= maxTries) {
      note = '';
      _answer(check.passed);
    } else {
      note = 'Quase! Fale de novo, com calma (tentativa ${tries + 1} de $maxTries).';
      notifyListeners();
    }
  }

  /// "Não posso falar agora": esta frase e as próximas viram exercícios de traduzir, por um tempo.
  void cantSpeakNow() {
    voice?.pausedUntil = DateTime.now().add(quietFor);
    _speakingOff('');
  }

  void _speakingOff(String message) {
    _stopListening();
    for (final card in _lesson.skip(_index)) {
      card.exercise = Exercise.translate;
    }
    _resetSpeaking();
    note = message;
    notifyListeners();
  }

  void _resetSpeaking() {
    hearing = '';
    speech = null;
    tries = 0;
  }

  /// Acertou: o quiz passa a começar depois desta frase. Errou: ela volta no fim da lição (uma vez).
  void _answer(bool ok) {
    final card = _card!;
    correct = ok;
    answered++;
    if (ok) {
      right++;
      if (_saveProgress && card.item.position > prefs.quizPos) prefs.quizPos = card.item.position;
    } else if (_retried.add(card.item.position)) {
      _lesson.add(_Card(card.item, card.exercise));
    }
    notifyListeners();
  }

  /// Arquiva a frase atual na API: ela não aparece mais nas lições (nem volta no fim desta). Sem
  /// resposta ainda, a lição passa para a próxima frase, sem contar como resposta. false: não deu
  /// (o motivo fica em [note]).
  Future<bool> archiveCurrent() async {
    final card = _card;
    if (card == null || archiving) return false;
    _stopListening();
    archiving = true;
    note = '';
    notifyListeners();
    try {
      await api.archive(card.item.id);
    } on ApiFailure catch (e) {
      if (_closed) return false;
      archiving = false;
      note = 'Não deu para arquivar: ${e.message}';
      notifyListeners();
      return false;
    }
    if (_closed) return true;
    archiving = false;
    final keep = _index + (correct == null ? 0 : 1); // respondida: ela fica, e não volta no fim
    _lesson = [
      ..._lesson.take(keep),
      for (final c in _lesson.skip(keep))
        if (c.item.id != card.item.id) c,
    ];
    if (correct == null) {
      picked.clear();
      _resetSpeaking();
      turn++;
      if (_lesson.isEmpty) {
        await start(at: _saveProgress ? null : _from); // arquivou a lição inteira: vem a próxima
        return true;
      }
    }
    notifyListeners();
    return true;
  }

  /// Vai para a próxima frase (depois de responder).
  void next() {
    if (correct == null) return;
    turn++;
    _index++;
    picked.clear();
    correct = null;
    note = '';
    _stopListening();
    _resetSpeaking();
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _stopListening();
    level.dispose();
    super.dispose();
  }
}
