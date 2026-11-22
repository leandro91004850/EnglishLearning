import 'dart:io';

import '../data/json_file.dart';

/// Onde está a API do Legendas YT (o servidor em Python, projeto api_english) e a chave de
/// acesso dela. Ficam no aparelho, no servidor.json da pasta privada do app; dá para mudar em
/// ⋮ › Servidor.
class ApiSettings {
  const ApiSettings({this.url = '', this.token = ''});

  factory ApiSettings.read(File file) {
    final data = readJson<Map<String, dynamic>>(file, const {});
    String str(Object? value) => value is String ? value.trim() : '';
    return ApiSettings(url: str(data['url']), token: str(data['chave']));
  }

  /// Endereço da API, sem a barra no fim: "http://192.168.0.10:8000".
  final String url;

  /// Chave de acesso (o API_TOKEN do .env da API); vazia se a API não pede chave.
  final String token;

  bool get configured => url.isNotEmpty;

  bool write(File file) => writeJson(file, {'url': url, 'chave': token});

  static final RegExp _trailingSlashes = RegExp(r'/+$');
  static final RegExp _space = RegExp(r'\s');

  /// Dados da tela ⋮ › Servidor -> configuração, ou o motivo do erro. A chave em branco mantém a
  /// que está gravada.
  static (ApiSettings, String) fromForm(String url, String token, ApiSettings current) {
    var text = url.trim();
    if (text.isEmpty) return (current, 'Informe o endereço da API, por exemplo http://192.168.0.10:8000.');
    if (!text.contains('://')) text = 'http://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
      return (current, 'Endereço inválido: use algo como http://192.168.0.10:8000.');
    }
    final key = token.trim();
    if (key.contains(_space)) return (current, 'A chave de acesso não pode ter espaços.');
    final base = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path.replaceFirst(_trailingSlashes, ''),
    );
    return (ApiSettings(url: base.toString(), token: key.isEmpty ? current.token : key), '');
  }
}
