import 'dart:io' show Platform;

import 'package:flutter_tts/flutter_tts.dart';

import '../core/log.dart';

/// Lê a frase em inglês (o alto-falante do quiz) com a voz do aparelho.
abstract class Speaker {
  Future<void> say(String text);
  Future<void> stop();
}

class DeviceSpeaker implements Speaker {
  FlutterTts? _tts;

  Future<FlutterTts> _ready() async {
    final current = _tts;
    if (current != null) return current;
    final tts = FlutterTts();
    await tts.setLanguage('en-US');
    await tts.setSpeechRate(0.45);
    if (Platform.isIOS) {
      // toca mesmo com o iPhone no silencioso, como o vídeo
      await tts.setSharedInstance(true);
      await tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [IosTextToSpeechAudioCategoryOptions.mixWithOthers],
      );
    }
    return _tts = tts;
  }

  @override
  Future<void> say(String text) async {
    try {
      final tts = await _ready();
      await tts.stop();
      await tts.speak(text);
    } catch (e) {
      Log.warning('Voz do quiz: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {
      // nada a parar
    }
  }
}

/// Sem voz (testes).
class SilentSpeaker implements Speaker {
  final List<String> said = [];

  @override
  Future<void> say(String text) async => said.add(text);

  @override
  Future<void> stop() async {}
}
