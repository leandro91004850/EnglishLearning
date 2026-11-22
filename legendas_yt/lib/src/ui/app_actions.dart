import 'package:material_ui/material_ui.dart';

import '../app/services.dart';
import 'diagnostics_page.dart';
import 'server_page.dart';

/// O que aparece no menu inicial e no ⋮ da tela dos vídeos.

void openServer(BuildContext context, AppServices services) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ServerPage(services: services)));
}

void openDiagnostics(BuildContext context, AppServices services, {String? url}) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => DiagnosticsPage(diagnostics: services.diagnostics(), url: url),
  ));
}

void showAbout(BuildContext context) {
  showAboutDialog(
    context: context,
    applicationName: 'Legendas YT',
    applicationVersion: '1.1.0',
    applicationIcon: ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: Image.asset('assets/icone.png', width: 48, height: 48),
    ),
    children: const [
      SizedBox(height: 8),
      Text(
        'Abre o vídeo do YouTube e mostra, junto com o vídeo, a fala original e a tradução '
        '(inglês ⇄ português). Em "Lições", exercícios sorteados com as frases dos seus vídeos, das '
        'palavras que mais se repetem nas legendas para as que menos: montar a tradução e repetir a '
        'frase em voz alta (o reconhecimento de voz do aparelho, gratuito, confere a pronúncia).\n\n'
        'A legenda e a tradução vêm do servidor do Legendas YT (a API, em Servidor), que guarda '
        'tudo no banco de dados. Tradução: Google Tradutor gratuito; quando ele falha, a reserva '
        'MyMemory (até 5.000 caracteres por dia).\n\n'
        'Atalhos: espaço tocar/pausar · ← → fala anterior/próxima · R repetir · F tela cheia · + − tamanho da legenda.',
      ),
    ],
  );
}
