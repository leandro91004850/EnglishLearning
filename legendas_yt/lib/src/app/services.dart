import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';

import '../core/diagnostics.dart';
import '../core/log.dart';
import '../data/banco.dart';
import '../data/history.dart';
import '../data/prefs.dart';
import '../data/translation_cache.dart';
import '../translation/translator.dart';
import '../youtube/transcript_api.dart';
import 'session.dart';

/// Tudo o que o app usa, criado uma vez na abertura. Os arquivos ficam na
/// pasta de dados do app (o `data_dir()` do app.py): historico.json,
/// preferencias.json, legendas-yt.log, cache/ e o .env com os dados de acesso
/// ao banco de dados (PostgreSQL).
class AppServices {
  AppServices._({
    required this.dir,
    required this.envFile,
    required this.banco,
    required this.history,
    required this.prefs,
    required this.cache,
    required this.translation,
    required this.transcripts,
    required this.session,
  }) {
    banco.onStatus = (message) => dbStatus.value = message;
  }

  static Future<AppServices> create({Directory? dir, http.Client? client, Banco? banco}) async {
    final base = dir ?? await getApplicationSupportDirectory();
    Log.openFile(File('${base.path}/legendas-yt.log'));
    if (kDebugMode) Log.echo = debugPrint;

    final http.Client c = client ??
        IOClient(HttpClient()..connectionTimeout = const Duration(seconds: 6));
    final envFile = File('${base.path}/.env');
    final db = banco ?? Banco.fromEnv(envFile, mobile: !kIsWeb && (Platform.isIOS || Platform.isAndroid));
    final history = History(File('${base.path}/historico.json'))..attach(db);
    final prefs = Prefs(File('${base.path}/preferencias.json'))..attach(db);
    final cache = TranslationCache(Directory('${base.path}/cache'));
    unawaited(cache.prune({for (final x in history.items) x.id}));
    final translation = TranslationService(client: c);
    final transcripts = TranscriptApi(client: c);
    final services = AppServices._(
      dir: base,
      envFile: envFile,
      banco: db,
      history: history,
      prefs: prefs,
      cache: cache,
      translation: translation,
      transcripts: transcripts,
      session: SubtitleSession(
        history: history,
        cache: cache,
        transcripts: transcripts,
        translation: translation,
        client: c,
        banco: db,
      ),
    );
    unawaited(services.openDb()); // na abertura, sem segurar a tela
    return services;
  }

  final Directory dir;

  /// Os dados de acesso ao banco (oculto, só na pasta de dados do app).
  final File envFile;
  final Banco banco;
  final History history;
  final Prefs prefs;
  final TranslationCache cache;
  final TranslationService translation;
  final TranscriptApi transcripts;
  final SubtitleSession session;

  /// Problema com o banco de dados, para o aviso na tela ("" = tudo certo).
  final ValueNotifier<String> dbStatus = ValueNotifier('');

  Diagnostics diagnostics() => Diagnostics(translation: translation, transcripts: transcripts, banco: banco);

  /// Conecta ao banco e lê a lista de recentes e as preferências (na abertura do
  /// app e quando os dados de acesso mudam pela tela).
  Future<void> openDb() async {
    if (!banco.configured) return;
    try {
      await history.loadFromDb();
      await prefs.loadFromDb();
      history.save(); // o que ficou só no aparelho vai para o banco
    } catch (e) {
      Log.warning('Abertura do banco de dados: $e');
    }
  }

  /// Ao fechar o app: grava onde o vídeo parou e espera as gravações pendentes.
  Future<void> shutdown() async {
    history.save();
    if (!await banco.flush(const Duration(seconds: 5))) {
      Log.warning('Banco de dados: o app fechou com gravações pendentes');
    }
  }

  // ---- tela do banco de dados ----

  /// Dados de acesso para a tela. A senha não vai para a tela: só se existe.
  Map<String, Object> dbConfig() {
    final c = banco.config;
    String or(String key, String fallback) => (c[key] ?? '').isEmpty ? fallback : c[key]!;
    return {
      'host': or('DB_HOST', 'localhost'),
      'port': or('DB_PORT', '5432'),
      'dbname': or('DB_NAME', 'legendas_yt'),
      'user': or('DB_USER', 'postgres'),
      'sslmode': c['DB_SSLMODE'] ?? '',
      'hasPassword': (c['DB_PASSWORD'] ?? '').isNotEmpty,
    };
  }

  /// Testa os dados da tela sem gravá-los: conecta (criando o banco e as
  /// tabelas, se faltarem) e conta o que já está guardado.
  Future<(bool, String)> testDb(Map<String, Object?> form) async {
    final (config, error) = configFromForm(form, banco.config);
    if (error.isNotEmpty) return (false, error);
    final test = Banco(config, mobile: banco.mobile);
    try {
      final (ok, message) = await test.check();
      return (ok, ok ? 'Conectou: $message.' : message);
    } finally {
      await test.close();
    }
  }

  /// Grava os dados da tela no .env e passa a usar esse banco na hora.
  /// Devolve (gravou, conectou, mensagem).
  Future<(bool, bool, String)> saveDb(Map<String, Object?> form) async {
    final (config, error) = configFromForm(form, banco.config);
    if (error.isNotEmpty) return (false, false, error);
    try {
      writeEnv(envFile, config);
    } on FileSystemException catch (e) {
      Log.warning('Não consegui gravar ${envFile.path}: $e');
      return (false, false, 'Não consegui gravar os dados de acesso: ${e.message}');
    }
    Log.info('Banco de dados: dados de acesso trocados pela tela '
        '(${config['DB_USER']}@${config['DB_HOST']}:${config['DB_PORT']}/${config['DB_NAME']})');
    history.save(); // o que ainda não tinha ido para o banco anterior vai agora
    await banco.flush(const Duration(seconds: 5));
    await banco.reconfigure(config);
    history.dbReset();
    prefs.dbReset();
    await openDb();
    final (ok, message) = await banco.check();
    return (
      true,
      ok,
      ok ? 'Gravado. Conectou: $message.' : 'Gravado, mas o app não conseguiu conectar. $message',
    );
  }
}
