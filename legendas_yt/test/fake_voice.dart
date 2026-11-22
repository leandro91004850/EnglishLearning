import 'dart:async';

import 'package:legendas_yt/src/quiz/voice_input.dart';

/// Um microfone de mentira: cada vez que liga, "ouve" o próximo item do [script] — uma lista de
/// transcrições (a mais provável primeiro) ou um texto de erro. Sem script, fica ouvindo até
/// [stop] (e aí não ouviu nada).
class FakeVoice extends VoiceInput {
  FakeVoice({this.allowed = true});

  /// A permissão do microfone.
  bool allowed;

  final List<Object> script = [];
  int listens = 0;
  int cancels = 0;
  void Function(Heard heard)? _waiting;

  @override
  Future<bool> ready() async => allowed;

  @override
  Future<void> listen({
    required void Function(Heard heard) onHeard,
    required void Function(String message) onError,
    void Function(double level)? onLevel,
  }) async {
    listens++;
    if (script.isEmpty) {
      _waiting = onHeard;
      return;
    }
    final next = script.removeAt(0);
    scheduleMicrotask(() {
      onLevel?.call(0.6);
      if (next is String) {
        onError(next);
        return;
      }
      final texts = next as List<String>;
      if (texts.isNotEmpty) onHeard(Heard([texts.first]));
      onHeard(Heard(texts, done: true));
    });
  }

  @override
  Future<void> stop() async {
    final waiting = _waiting;
    _waiting = null;
    waiting?.call(const Heard([], done: true));
  }

  @override
  Future<void> cancel() async {
    cancels++;
    _waiting = null;
  }
}
