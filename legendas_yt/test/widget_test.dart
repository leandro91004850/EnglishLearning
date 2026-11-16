import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:legendas_yt/main.dart';
import 'package:legendas_yt/src/app/services.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('abre vazio, em português, e recusa link inválido', (tester) async {
    final dir = Directory.systemTemp.createTempSync('legendas_widget');
    addTearDown(() => dir.deleteSync(recursive: true));
    final services = (await tester.runAsync(
      () => AppServices.create(dir: dir, client: MockClient((_) async => http.Response('', 500))),
    ))!;

    await tester.pumpWidget(LegendasApp(services: services));
    await tester.pump();

    expect(find.text('Cole um link do YouTube e toque em Abrir'), findsOneWidget);
    expect(find.text('Abrir'), findsOneWidget);
    expect(find.text('Recentes'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'isto não é um link');
    await tester.tap(find.text('Abrir'));
    await tester.pump();
    expect(find.text('Link do YouTube inválido.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
