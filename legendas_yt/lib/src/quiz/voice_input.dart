/// O microfone das lições: ouve a pessoa falar a frase em inglês com o reconhecimento de voz do
/// próprio aparelho (o da Apple no iPhone e no Mac, o do Google no Android), pelo plugin
/// speech_to_text: gratuito, sem chave e sem servidor nosso.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../core/log.dart';

/// O que o aparelho ouviu: as transcrições possíveis, a mais provável primeiro.
class Heard {
  const Heard(this.transcripts, {this.done = false});

  final List<String> transcripts;

  /// O resultado final: o aparelho parou de ouvir (vazio se não entendeu nada).
  final bool done;

  String get text => transcripts.isEmpty ? '' : transcripts.first;
}

abstract class VoiceInput {
  /// "Não posso falar agora": sem exercícios de falar até esta hora.
  DateTime? pausedUntil;

  /// Sem permissão do microfone ou sem reconhecimento de voz neste aparelho.
  bool blocked = false;

  /// Dá para ter exercícios de falar agora.
  bool get available => !blocked && !(pausedUntil?.isAfter(DateTime.now()) ?? false);

  /// Prepara o reconhecimento; na primeira vez o aparelho pede as permissões do microfone e do
  /// reconhecimento de voz. false: sem permissão ou sem reconhecimento de voz.
  Future<bool> ready();

  /// Ouve até a pessoa parar de falar (ou até [stop]). [onHeard] recebe o que vai sendo ouvido
  /// e, no fim, o resultado final ([Heard.done]). [onError]: não deu para ouvir (a mensagem para a
  /// tela). [onLevel]: o volume da voz, de 0 a 1.
  Future<void> listen({
    required void Function(Heard heard) onHeard,
    required void Function(String message) onError,
    void Function(double level)? onLevel,
  });

  /// Para de ouvir e entrega o que foi ouvido.
  Future<void> stop();

  /// Para de ouvir sem entregar nada.
  Future<void> cancel();
}

/// O reconhecimento de voz do aparelho.
class DeviceVoiceInput extends VoiceInput {
  DeviceVoiceInput._();

  /// Um só para o app todo: o reconhecimento de voz do aparelho é um só, e o "não posso falar
  /// agora" vale para todas as lições.
  static final DeviceVoiceInput instance = DeviceVoiceInput._();

  final SpeechToText _speech = SpeechToText();
  bool _ready = false;
  _Listening? _current;

  @override
  Future<bool> ready() async {
    if (_ready) return true;
    try {
      _ready = await _speech.initialize(
        onError: _error,
        onStatus: _status,
        finalTimeout: const Duration(milliseconds: 1500),
      );
    } catch (e) {
      Log.warning('Reconhecimento de voz: $e');
      _ready = false;
    }
    if (!_ready) Log.warning('Reconhecimento de voz indisponível (sem permissão ou sem suporte no aparelho)');
    return _ready;
  }

  static const Duration _listenFor = Duration(seconds: 15);

  /// Depois que o plugin para de ouvir, quanto esperar pelo resultado final.
  static const Duration _finalWait = Duration(milliseconds: 2500);

  @override
  Future<void> listen({
    required void Function(Heard heard) onHeard,
    required void Function(String message) onError,
    void Function(double level)? onLevel,
  }) async {
    await cancel();
    final listening = _current = _Listening(onHeard, onError);
    try {
      await _speech.listen(
        onResult: (result) => _result(listening, result),
        onSoundLevelChange: onLevel == null ? null : (db) => onLevel(_level(db)),
        listenOptions: SpeechListenOptions(
          localeId: 'en_US',
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
          autoPunctuation: false,
          listenFor: _listenFor,
          pauseFor: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      Log.warning('Reconhecimento de voz: $e');
      _finish(listening, error: 'Não deu para ligar o microfone. Tente de novo.');
      return;
    }
    _watch(listening);
  }

  /// O plugin nem sempre avisa quando para de ouvir sem ter ouvido nada (ele para sozinho depois
  /// de uns segundos de silêncio). Se ele parou e o resultado final não veio, termina com o que
  /// foi ouvido até ali; e nunca fica ouvindo mais que [_listenFor] e um pouco.
  void _watch(_Listening listening) {
    final started = DateTime.now();
    DateTime? stoppedAt;
    listening.watchdog = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (_current != listening) {
        timer.cancel();
        return;
      }
      final now = DateTime.now();
      if (_speech.isListening) {
        stoppedAt = null;
      } else {
        stoppedAt ??= now;
      }
      final waitedFinal = stoppedAt != null && now.difference(stoppedAt!) >= _finalWait;
      final tooLong = now.difference(started) >= _listenFor + const Duration(seconds: 5);
      if (waitedFinal || tooLong) {
        if (_speech.isListening) unawaited(_speech.cancel());
        _finish(listening);
      }
    });
  }

  @override
  Future<void> stop() async {
    try {
      await _speech.stop();
    } catch (e) {
      Log.warning('Reconhecimento de voz: $e');
    }
  }

  @override
  Future<void> cancel() async {
    _current?.watchdog?.cancel();
    _current = null;
    if (!_ready) return;
    try {
      await _speech.cancel();
    } catch (e) {
      Log.warning('Reconhecimento de voz: $e');
    }
  }

  void _result(_Listening listening, SpeechRecognitionResult result) {
    if (_current != listening) return;
    final texts = [
      for (final alternate in result.alternates)
        if (alternate.recognizedWords.trim().isNotEmpty) alternate.recognizedWords.trim(),
    ];
    if (texts.isNotEmpty) listening.last = texts;
    if (result.finalResult) {
      _finish(listening);
    } else {
      listening.onHeard(Heard(listening.last));
    }
  }

  void _status(String status) {
    final listening = _current;
    if (listening == null || status != SpeechToText.doneStatus) return;
    // terminou sem resultado final: o erro, se houver, chega logo depois do "done"
    Timer(const Duration(milliseconds: 400), () => _finish(listening));
  }

  void _error(SpeechRecognitionError error) {
    final listening = _current;
    if (listening == null) return;
    Log.info('Reconhecimento de voz: ${error.errorMsg}');
    _finish(listening, error: _nothingHeard.contains(error.errorMsg) ? null : _message(error.errorMsg));
  }

  void _finish(_Listening listening, {String? error}) {
    if (_current != listening) return;
    _current = null;
    listening.watchdog?.cancel();
    if (error != null && listening.last.isEmpty) {
      listening.onError(error);
    } else {
      listening.onHeard(Heard(listening.last, done: true));
    }
  }

  /// O volume em dB (iPhone e Mac: de uns -50, silêncio, a 0; Android: de -2 a 10) -> 0 a 1.
  static double _level(double db) {
    final value = Platform.isAndroid ? (db + 2) / 12 : (db + 50) / 40;
    return value.isNaN ? 0 : value.clamp(0.0, 1.0);
  }

  /// Erros que só querem dizer "não entendi nada".
  static const Set<String> _nothingHeard = {'error_no_match', 'error_speech_timeout', 'error_retry'};

  static String _message(String code) {
    if (code.contains('network') || code.contains('server') || code.contains('connection') || code.contains('too_many')) {
      return 'O reconhecimento de voz precisa de internet agora. Verifique a conexão e tente de novo.';
    }
    if (code.contains('permission') || code.contains('not_authorized') || code.contains('disabled')) {
      return 'O reconhecimento de voz está desligado ou sem permissão. Libere nos Ajustes do aparelho.';
    }
    if (code.contains('language') || code.contains('assets')) {
      return 'O inglês não está disponível no reconhecimento de voz deste aparelho.';
    }
    if (code.contains('busy') || code.contains('already_active')) {
      return 'O microfone está ocupado. Tente de novo.';
    }
    if (code.contains('listen_failed') || code.contains('audio')) {
      return 'Não deu para ligar o microfone. Veja se outro app está usando o microfone e tente de novo.';
    }
    return 'Não deu para ouvir ($code). Tente de novo.';
  }
}

class _Listening {
  _Listening(this.onHeard, this.onError);

  final void Function(Heard heard) onHeard;
  final void Function(String message) onError;

  /// As transcrições mais recentes.
  List<String> last = const [];

  Timer? watchdog;
}
