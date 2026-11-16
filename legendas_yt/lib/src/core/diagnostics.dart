/// O `python app.py --diagnostico [link]`: testa os tradutores e, com um link,
/// as legendas do vídeo. Usado pela tela de diagnóstico e por
/// `dart run bin/diagnostico.dart [link]`.
library;

import 'dart:convert';

import '../translation/translator.dart';
import '../youtube/transcript_api.dart';
import '../youtube/video_id.dart';
import 'subtitles.dart';
import 'text.dart';

class Diagnostics {
  Diagnostics({required this.translation, required this.transcripts});

  final TranslationService translation;
  final TranscriptApi transcripts;

  static const List<String> samples = [
    'Hello, how are you?',
    'I started listening more.',
    'Do you understand English but feel',
  ];

  /// Quantos tradutores responderam (pelo menos um precisa estar OK).
  int translatorsOk = 0;

  Stream<String> run({String? url}) async* {
    translatorsOk = 0;
    yield 'Legendas YT — diagnóstico';
    yield '';

    final results = <(bool, DateTime?)>[];
    for (final MapEntry(key: name, value: engine) in translation.engines.entries) {
      final (line, ok, until) = await _check(name, engine);
      results.add((ok, until));
      yield line;
    }
    DateTime? blocked;
    for (final (_, until) in results) {
      if (until != null && (blocked == null || until.isAfter(blocked))) blocked = until;
    }
    if (blocked != null) {
      yield '        O Google bloqueou temporariamente este IP por excesso de pedidos. '
          'Tente de novo depois das ${hourMinute(blocked)}; enquanto isso o app usa a reserva '
          'e depois volta ao Google sozinho.';
    }
    for (final MapEntry(key: name, value: engine) in translation.reserve.entries) {
      final (line, ok, until) = await _check(name, engine);
      results.add((ok, until));
      yield line;
    }
    translatorsOk = results.where((r) => r.$1).length;

    if (url != null && url.trim().isNotEmpty) {
      final vid = extractVideoId(url);
      if (vid == null) {
        yield '[FALHA] Legendas do YouTube: link inválido';
      } else {
        try {
          final tracks = await transcripts.list(vid);
          final names = tracks.map((t) => '$t').join(', ');
          final track = pickTranscript(tracks, 'auto', vid);
          final n = (await transcripts.fetch(track)).length;
          yield '[OK]    Legendas do YouTube: $n falas em ${track.languageCode} (disponíveis: $names)';
        } catch (e) {
          final name = e is TranscriptError ? e.name : '${e.runtimeType}';
          yield '[FALHA] Legendas do YouTube: ${friendlyError(e)} [$name]';
        }
      }
    }

    yield '';
    yield 'Pelo menos um tradutor precisa estar OK para o app traduzir. O MyMemory é só a '
        'reserva: até ${thousands(myMemoryDailyChars)} caracteres por dia sem cadastro '
        '(umas 200 falas), usados quando o Google falha.';
  }

  /// Traduz as amostras: (linha do relatório, deu certo?, até quando o Google bloqueia).
  Future<(String, bool, DateTime?)> _check(String name, Engine engine) async {
    final watch = Stopwatch()..start();
    try {
      final out = await engine(samples, 'en', 'pt');
      final secs = (watch.elapsedMilliseconds / 1000).toStringAsFixed(1);
      return ('[OK]    $name, $secs s: ${jsonEncode(out)}', true, null);
    } on TranslateError catch (e) {
      return ('[FALHA] $e', false, e is RateLimited ? e.until : null);
    } catch (e) {
      return ('[FALHA] $name: $e', false, null);
    }
  }
}
