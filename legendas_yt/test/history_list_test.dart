import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legendas_yt/src/data/history.dart';
import 'package:legendas_yt/src/ui/widgets/history_list.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_banco.dart';

void main() {
  testWidgets('segurar e arrastar um vídeo muda a ordem; toque rápido abre', (tester) async {
    final dir = Directory.systemTemp.createTempSync('legendas_drag');
    addTearDown(() => dir.deleteSync(recursive: true));
    final history = History(File('${dir.path}/historico.json'));
    for (final (id, title) in [
      ('ccccccccccc', 'Vídeo C'),
      ('bbbbbbbbbbb', 'Vídeo B'),
      ('aaaaaaaaaaa', 'Vídeo A'),
    ]) {
      history.opened(id, 'auto');
      history.update(id, title: title);
    }
    List<String> order() => [for (final x in history.items) x.id];
    expect(order(), ['aaaaaaaaaaa', 'bbbbbbbbbbb', 'ccccccccccc']);

    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HistoryList(
          history: history,
          currentId: null,
          onOpen: (item) => opened.add(item.id),
          onRemove: (_) {},
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Toque e segure um vídeo para arrastar e mudar a ordem.'), findsOneWidget);

    // segura o A e arrasta até depois do C
    final from = tester.getCenter(find.text('Vídeo A'));
    final to = tester.getCenter(find.text('Vídeo C'));
    final gesture = await tester.startGesture(from);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    const steps = 12;
    final distance = to.dy - from.dy + 50;
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(Offset(0, distance / steps));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(order(), ['bbbbbbbbbbb', 'ccccccccccc', 'aaaaaaaaaaa']);
    expect(opened, isEmpty, reason: 'segurar para arrastar não abre o vídeo');
    expect([for (final x in History(File('${dir.path}/historico.json')).items) x.id], order(),
        reason: 'a nova ordem já foi gravada');

    // um toque rápido continua abrindo o vídeo
    await tester.tap(find.text('Vídeo B'));
    await tester.pumpAndSettle();
    expect(opened, ['bbbbbbbbbbb']);
  });

  testWidgets('com o banco de dados a lista não tem ×; sem ele, tem', (tester) async {
    final dir = Directory.systemTemp.createTempSync('legendas_x');
    addTearDown(() => dir.deleteSync(recursive: true));
    final history = History(File('${dir.path}/historico.json'))..opened('aaaaaaaaaaa', 'auto');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HistoryList(history: history, currentId: null, onOpen: (_) {}, onRemove: (_) {}),
      ),
    ));
    expect(find.byTooltip('Tirar da lista'), findsOneWidget);

    history
      ..attach(FakeBanco())
      ..dbReset(); // como depois de gravar os dados de acesso
    await tester.pump();
    expect(find.byTooltip('Tirar da lista'), findsNothing);
  });
}
