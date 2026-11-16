import 'dart:convert';
import 'dart:io';

import '../core/log.dart';
import '../core/subtitles.dart';
import 'json_file.dart';

/// Legenda e tradução completas de um vídeo.
class CachedSubtitles {
  const CachedSubtitles(this.meta, this.pairs, this.doneMessage);

  factory CachedSubtitles.fromJson(Map<String, dynamic> json) => CachedSubtitles(
        SubtitleMeta.fromJson(json['meta'] as Map<String, dynamic>),
        [
          for (final p in json['pairs'] as List)
            ((p as List)[0] as int, p[1] as String),
        ],
        json['done'] as String,
      );

  final SubtitleMeta meta;
  final List<(int, String)> pairs;
  final String doneMessage;

  Map<String, Object> toJson() => {
        'meta': meta.toJson(),
        'pairs': [for (final (i, t) in pairs) [i, t]],
        'done': doneMessage,
      };
}

/// Traduções já terminadas, por (vídeo, idioma de origem), para não traduzir de
/// novo. O app.py guardava em memória enquanto estava aberto; aqui também fica
/// em disco, porque no celular o sistema fecha o app com frequência e cada
/// tradução gasta a cota do Google.
class TranslationCache {
  TranslationCache(this.dir);

  final Directory dir;
  final Map<String, CachedSubtitles> _memory = {};

  File _file(String videoId, String source) => File('${dir.path}/${videoId}_$source.json');

  Future<CachedSubtitles?> get(String videoId, String source) async {
    final key = '$videoId|$source';
    final hit = _memory[key];
    if (hit != null) return hit;
    final file = _file(videoId, source);
    try {
      if (!await file.exists()) return null;
      final cached = CachedSubtitles.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
      _memory[key] = cached;
      return cached;
    } catch (e) {
      Log.warning('Cache ilegível (${file.path}): $e');
      return null;
    }
  }

  void put(String videoId, String source, CachedSubtitles value) {
    _memory['$videoId|$source'] = value;
    writeJson(_file(videoId, source), value.toJson());
  }

  /// Apaga o que não é de nenhum vídeo em [keep] (os da lista de recentes).
  Future<void> prune(Set<String> keep) async {
    _memory.removeWhere((key, _) => !keep.contains(key.split('|').first));
    try {
      if (!await dir.exists()) return;
      await for (final entry in dir.list()) {
        final name = entry.uri.pathSegments.last;
        if (entry is File && name.length > 11 && !keep.contains(name.substring(0, 11))) {
          await entry.delete();
        }
      }
    } on FileSystemException catch (e) {
      Log.warning('Não consegui limpar o cache: $e');
    }
  }
}
