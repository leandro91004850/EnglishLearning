import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import '../api/api_settings.dart';
import '../core/diagnostics.dart';
import '../core/log.dart';
import '../data/history.dart';
import '../data/prefs.dart';
import 'session.dart';

/// Tudo o que o app usa, criado uma vez na abertura. O app é só um consumidor da API do Legendas
/// YT: a lista de vídeos, as preferências e as legendas com a tradução vêm de lá. No aparelho
/// ficam só o endereço da API (servidor.json) e o registro (legendas-yt.log).
class AppServices {
  AppServices._({
    required this.dir,
    required this.settingsFile,
    required this.client,
    required this.api,
    required this.history,
    required this.prefs,
    required this.session,
  });

  static Future<AppServices> create({Directory? dir, http.Client? client}) async {
    final base = dir ?? await getApplicationSupportDirectory();
    Log.openFile(File('${base.path}/legendas-yt.log'));
    if (kDebugMode) Log.echo = debugPrint;

    final http.Client c = client ?? IOClient(HttpClient()..connectionTimeout = const Duration(seconds: 6));
    final settingsFile = File('${base.path}/servidor.json');
    final api = ApiClient(
      c,
      ApiSettings.read(settingsFile),
      mobile: !kIsWeb && (Platform.isIOS || Platform.isAndroid),
    );
    final history = History(api);
    final services = AppServices._(
      dir: base,
      settingsFile: settingsFile,
      client: c,
      api: api,
      history: history,
      prefs: Prefs(api),
      session: SubtitleSession(api: api, history: history),
    );
    services.ready = services.connect(); // na abertura, sem segurar a tela
    return services;
  }

  final Directory dir;

  /// O endereço da API e a chave de acesso (na pasta privada do app).
  final File settingsFile;

  /// O HTTP do app (os testes trocam por um de mentira).
  final http.Client client;
  final ApiClient api;
  final History history;
  final Prefs prefs;
  final SubtitleSession session;

  /// A primeira leitura da lista de vídeos e das preferências terminou (deu certo ou não).
  late Future<void> ready;

  /// Problema com a API ou com o banco de dados dela, para o aviso na tela ("" = tudo certo).
  final ValueNotifier<String> apiStatus = ValueNotifier('');

  ApiSettings get settings => api.settings;

  Diagnostics diagnostics() => Diagnostics(api);

  /// Lê a lista de vídeos e as preferências da API (na abertura e quando o endereço muda).
  Future<void> connect() async {
    if (!api.settings.configured) {
      apiStatus.value = ApiClient.notConfigured;
      return;
    }
    apiStatus.value = await history.load();
    await prefs.load();
  }

  /// Ao fechar o app: manda onde o vídeo parou e espera os envios pendentes.
  Future<void> shutdown() async {
    if (!await history.flush()) Log.warning('API: o app fechou com envios pendentes');
  }

  // ---- tela do servidor ----

  /// Testa o endereço e a chave da tela sem gravá-los: a API responde e diz como está o banco.
  Future<(bool, String)> testServer(String url, String token) async {
    final (settings, error) = ApiSettings.fromForm(url, token, api.settings);
    if (error.isNotEmpty) return (false, error);
    final test = ApiClient(client, settings, mobile: api.mobile);
    try {
      final status = await test.status(check: true);
      final db = status.dbOk
          ? 'Banco de dados: ${status.dbMessage}.'
          : 'Mas o banco de dados da API tem um problema: ${status.dbMessage}';
      return (true, 'Conectou à API ${status.version}. $db');
    } on ApiFailure catch (e) {
      return (false, e.message);
    }
  }

  /// Grava o endereço e a chave da tela e passa a usar essa API na hora.
  /// Devolve (gravou, conectou, mensagem).
  Future<(bool, bool, String)> saveServer(String url, String token) async {
    final (settings, error) = ApiSettings.fromForm(url, token, api.settings);
    if (error.isNotEmpty) return (false, false, error);
    if (!settings.write(settingsFile)) {
      return (false, false, 'Não consegui gravar o endereço da API neste aparelho.');
    }
    Log.info('Servidor (API) trocado pela tela: ${settings.url}');
    await history.flush(); // o que ainda não tinha ido para a API anterior vai agora
    api.settings = settings;
    await connect();
    final (ok, message) = await testServer(settings.url, '');
    return (true, ok, ok ? 'Gravado. $message' : 'Gravado, mas o app não conseguiu falar com a API. $message');
  }
}
