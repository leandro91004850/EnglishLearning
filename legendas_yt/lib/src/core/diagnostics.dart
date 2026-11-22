/// O diagnóstico (⋮ › Diagnóstico): o app confere se alcança a API, e a API testa no servidor o
/// banco de dados, os tradutores e, com um link, as legendas do vídeo (o
/// `python app.py --diagnostico [link]` do legendas-yt).
library;

import '../api/api_client.dart';

class Diagnostics {
  Diagnostics(this.api);

  final ApiClient api;

  Stream<String> run({String? url}) async* {
    yield 'Legendas YT — diagnóstico';
    yield '';
    if (!api.settings.configured) {
      yield '[FALHA] ${ApiClient.notConfigured}';
      return;
    }
    try {
      final status = await api.status();
      yield '[OK]    API do Legendas YT ${status.version} em ${api.settings.url}';
    } on ApiFailure catch (e) {
      yield '[FALHA] ${e.message}';
      return;
    }
    yield '        Testes no servidor da API (podem levar alguns segundos):';
    try {
      final (ok, lines) = await api.diagnose(url);
      for (final line in lines) {
        yield line;
      }
      yield '';
      yield ok
          ? 'Pelo menos um tradutor está OK no servidor: a tradução funciona.'
          : 'Nenhum tradutor funcionou no servidor: as legendas vêm sem tradução até um deles voltar.';
    } on ApiFailure catch (e) {
      yield '[FALHA] Diagnóstico no servidor: ${e.message}';
    }
  }
}
