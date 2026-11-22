/// A legenda que a API entrega: as falas e os idiomas, e as opções do seletor de idioma.
library;

import 'cue.dart';

/// Idioma preferido da legenda original: "auto", "en" ou "pt".
const List<String> sourceOptions = ['auto', 'en', 'pt'];

String normalizeSource(String? source) => sourceOptions.contains(source) ? source! : 'auto';

/// As falas e os idiomas de uma legenda (o "meta" da API; o que o app.py mandava para a
/// interface em `onTranscript`).
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
}
