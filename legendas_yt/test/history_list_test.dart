import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legendas_yt/src/data/history.dart';
import 'package:legendas_yt/src/ui/widgets/history_list.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_api.dart';

void main() {
  testWidgets('segurar e arrastar um vídeo muda a ordem e manda para a API; toque rápido abre', (tester) async {
    final fake = FakeApi();
    final history = History(fake.api());
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
        body: HistoryList(history: history, currentId: null, onOpen: (item) => opened.add(item.id)),
      ),
    ));
    await tester.pump();
    expect(find.text('Toque e segure um vídeo para arrastar e mudar a ordem.'), findsOneWidget);
    expect(find.byTooltip('Tirar da lista'), findsNothing, reason: 'a lista tem todos os vídeos do banco: sem ×');

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
    await tester.runAsync(history.flush);
    expect(fake.orders.last, order(), reason: 'a nova ordem foi para a API');

    // um toque rápido continua abrindo o vídeo
    await tester.tap(find.text('Vídeo B'));
    await tester.pumpAndSettle();
    expect(opened, ['bbbbbbbbbbb']);
  });
}
