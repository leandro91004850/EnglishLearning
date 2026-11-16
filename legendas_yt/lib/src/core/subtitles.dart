/// Legendas: escolha da faixa, lotes para o tradutor e mensagens de erro
/// (portado de app.py).
library;

import '../youtube/transcript_api.dart';
import 'cue.dart';

const int chunkChars = 1200; // tamanho de cada lote enviado ao tradutor
const int chunkLines = 40;
const List<int> retryWaits = [5, 15, 30]; // novas tentativas para lotes que falharam (s)

/// Idioma preferido da legenda original: "auto", "en" ou "pt".
const List<String> sourceOptions = ['auto', 'en', 'pt'];

String normalizeSource(String? source) => sourceOptions.contains(source) ? source! : 'auto';

String langFamily(String code) => code.split('-').first.toLowerCase();

/// Inglês -> português; português -> inglês; qualquer outra -> português.
String targetFor(String sourceCode) => langFamily(sourceCode) == 'pt' ? 'en' : 'pt';

String targetName(String target) => target == 'pt' ? 'Português' : 'English';

int _compare(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return 0;
}

/// Escolhe a melhor faixa de legenda. [source] = "auto" | "en" | "pt"
///  - auto: prefere legenda feita por pessoas (EN ou PT) à gerada automaticamente.
///  - en/pt: prefere esse idioma, mesmo que seja gerado automaticamente.
/// Empate: fica a que vem antes (as feitas por pessoas vêm primeiro), como o min() do Python.
CaptionTrack pickTranscript(List<CaptionTrack> tracks, String source, String videoId) {
  if (tracks.isEmpty) throw NoTranscriptFound(videoId);
  final order = source == 'pt' ? const ['pt', 'en'] : const ['en', 'pt'];
  List<int> score(CaptionTrack t) {
    final fam = langFamily(t.languageCode);
    final rank = order.contains(fam) ? order.indexOf(fam) : order.length;
    final generated = t.isGenerated ? 1 : 0;
    if (source == 'auto') return [rank == order.length ? 1 : 0, generated, rank];
    return [rank, generated];
  }

  var best = tracks.first;
  var bestScore = score(best);
  for (final t in tracks.skip(1)) {
    final s = score(t);
    if (_compare(s, bestScore) < 0) {
      best = t;
      bestScore = s;
    }
  }
  return best;
}

final RegExp _parenthesis = RegExp(r'\s*\(.*?\)\s*$');
final RegExp _repeated = RegExp(r'^(.+?)\s+-\s+\1$');

/// "English (auto-generated)" -> "English". Faixa com nome igual ao idioma, que o
/// YouTube mostra como "English - English", também vira "English".
String languageName(CaptionTrack track) {
  final name = track.language.replaceFirst(_parenthesis, '').trim().replaceFirstMapped(_repeated, (m) => m[1]!);
  return name.isEmpty ? track.languageCode : name;
}

/// Agrupa [(índice, texto), ...] em lotes de até [chunkChars] caracteres / [chunkLines] falas.
List<List<(int, String)>> makeChunks(List<(int, String)> items) {
  final chunks = <List<(int, String)>>[];
  var cur = <(int, String)>[];
  var size = 0;
  for (final item in items) {
    final text = item.$2;
    if (cur.isNotEmpty && (size + text.length + 1 > chunkChars || cur.length >= chunkLines)) {
      chunks.add(cur);
      cur = <(int, String)>[];
      size = 0;
    }
    cur.add(item);
    size += text.length + 1;
  }
  if (cur.isNotEmpty) chunks.add(cur);
  return chunks;
}

String friendlyError(Object error) => switch (error) {
      TranscriptsDisabled() => 'Este vídeo não tem legendas (nem automáticas).',
      NoTranscriptFound() => 'Nenhuma legenda encontrada para este vídeo.',
      VideoUnavailable() => 'Vídeo indisponível.',
      AgeRestricted() => 'Vídeo com restrição de idade: legendas inacessíveis sem login.',
      RequestBlocked() =>
        'O YouTube bloqueou temporariamente as requisições deste IP. Tente mais tarde.',
      TranscriptNetworkError() =>
        'Erro ao buscar legendas: sem conexão com o YouTube. Confira a internet e clique em Abrir.',
      VideoUnplayable(:final reason) when reason != null && reason.isNotEmpty =>
        'Erro ao buscar legendas: VideoUnplayable ($reason)',
      YouTubeRequestFailed(:final statusCode) =>
        'Erro ao buscar legendas: YouTubeRequestFailed (HTTP $statusCode)',
      TranscriptError(:final name) => 'Erro ao buscar legendas: $name',
      _ => 'Erro ao buscar legendas: ${error.runtimeType}',
    };

/// O que o app.py mandava para a interface em `onTranscript`.
class SubtitleMeta {
  const SubtitleMeta({
    required this.cues,
    required this.sourceName,
    required this.sourceCode,
    required this.generated,
    required this.target,
    required this.targetName,
  });

  factory SubtitleMeta.fromJson(Map<String, dynamic> json) => SubtitleMeta(
        cues: [for (final c in json['cues'] as List) Cue.fromJson(c as Map<String, dynamic>)],
        sourceName: json['sourceName'] as String,
        sourceCode: json['sourceCode'] as String,
        generated: json['generated'] as bool,
        target: json['target'] as String,
        targetName: json['targetName'] as String,
      );

  final List<Cue> cues;
  final String sourceName;
  final String sourceCode;
  final bool generated;
  final String target;
  final String targetName;

  Map<String, Object> toJson() => {
        'cues': [for (final c in cues) c.toJson()],
        'sourceName': sourceName,
        'sourceCode': sourceCode,
        'generated': generated,
        'target': target,
        'targetName': targetName,
      };
}
