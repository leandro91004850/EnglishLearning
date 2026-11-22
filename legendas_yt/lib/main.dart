import 'package:material_ui/material_ui.dart';

import 'src/app/services.dart';
import 'src/ui/menu_page.dart';
import 'src/ui/theme.dart';

/// Legendas YT — legendas de vídeos do YouTube com tradução em tempo real (português ⇄ inglês)
/// e as lições (exercícios com as frases das legendas). Consumidor da API do Legendas YT.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.create();
  runApp(LegendasApp(services: services));
}

class LegendasApp extends StatelessWidget {
  const LegendasApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Legendas YT',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: MenuPage(services: services),
    );
  }
}
