import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';

import '../core/diagnostics.dart';
import '../core/log.dart';
import '../data/history.dart';
import '../data/prefs.dart';
import '../data/translation_cache.dart';
import '../translation/translator.dart';
import '../youtube/transcript_api.dart';
import 'session.dart';

/// Tudo o que o app usa, criado uma vez na abertura. Os arquivos ficam na
/// pasta de dados do app (o `data_dir()` do app.py): historico.json,
/// preferencias.json, legendas-yt.log e cache/.
class AppServices {
  AppServices._({
    required this.dir,
    required this.history,
    required this.prefs,
    required this.cache,
    required this.translation,
    required this.transcripts,
    required this.session,
  });

  static Future<AppServices> create({Directory? dir, http.Client? client}) async {
    final base = dir ?? await getApplicationSupportDirectory();
    Log.openFile(File('${base.path}/legendas-yt.log'));
    if (kDebugMode) Log.echo = debugPrint;

    final http.Client c = client ??
        IOClient(HttpClient()..connectionTimeout = const Duration(seconds: 6));
    final history = History(File('${base.path}/historico.json'));
    final cache = TranslationCache(Directory('${base.path}/cache'));
    unawaited(cache.prune({for (final x in history.items) x.id}));
    final translation = TranslationService(client: c);
    final transcripts = TranscriptApi(client: c);
    return AppServices._(
      dir: base,
      history: history,
      prefs: Prefs(File('${base.path}/preferencias.json')),
      cache: cache,
      translation: translation,
      transcripts: transcripts,
      session: SubtitleSession(
        history: history,
        cache: cache,
        transcripts: transcripts,
        translation: translation,
        client: c,
      ),
    );
  }

  final Directory dir;
  final History history;
  final Prefs prefs;
  final TranslationCache cache;
  final TranslationService translation;
  final TranscriptApi transcripts;
  final SubtitleSession session;

  Diagnostics diagnostics() => Diagnostics(translation: translation, transcripts: transcripts);
}
