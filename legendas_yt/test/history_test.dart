import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legendas_yt/src/data/history.dart';
import 'package:legendas_yt/src/data/prefs.dart';

void main() {
  late Directory dir;
  late DateTime now;
  File file() => File('${dir.path}/historico.json');
  History history({int limit = historyLimit}) => History(file(), limit: limit, now: () => now);
  List<String> ids(History h) => [for (final x in h.items) x.id];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('legendas_hist');
    now = DateTime(2026, 11, 15, 10);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('link novo entra no topo; aberto pela lista fica no lugar', () {
    final h = history();
    expect(h.opened('aaaaaaaaaaa', 'auto'), isTrue); // sem título ainda
    h.opened('bbbbbbbbbbb', 'auto');
    h.opened('ccccccccccc', 'en');
    expect(ids(h), ['ccccccccccc', 'bbbbbbbbbbb', 'aaaaaaaaaaa']);

    h.opened('aaaaaaaaaaa', 'pt', keepPlace: true);
    expect(ids(h), ['ccccccccccc', 'bbbbbbbbbbb', 'aaaaaaaaaaa']);
    expect(h.find('aaaaaaaaaaa')!.source, 'pt');

    h.opened('aaaaaaaaaaa', 'auto'); // colado de novo: sobe
    expect(ids(h).first, 'aaaaaaaaaaa');

    // aberto pela lista depois de sair dela: não volta
    h.remove('bbbbbbbbbbb');
    expect(h.opened('bbbbbbbbbbb', 'auto', keepPlace: true), isFalse);
    expect(ids(h), ['aaaaaaaaaaa', 'ccccccccccc']);
  });

  test('limite de vídeos, setas e o último assistido', () {
    final h = history(limit: 3);
    for (final id in ['aaaaaaaaaaa', 'bbbbbbbbbbb', 'ccccccccccc', 'ddddddddddd']) {
      now = now.add(const Duration(minutes: 1));
      h.opened(id, 'auto');
    }
    expect(ids(h), ['ddddddddddd', 'ccccccccccc', 'bbbbbbbbbbb']);

    expect(h.move('ddddddddddd', -1), isFalse); // já está no topo
    expect(h.move('ddddddddddd', 1), isTrue);
    expect(ids(h), ['ccccccccccc', 'ddddddddddd', 'bbbbbbbbbbb']);
    expect(h.latest!.id, 'ddddddddddd'); // mover não muda o `at`

    now = now.add(const Duration(minutes: 1));
    h.opened('bbbbbbbbbbb', 'auto', keepPlace: true);
    expect(h.latest!.id, 'bbbbbbbbbbb');
    expect(ids(h).last, 'bbbbbbbbbbb');
  });

  test('posição: grava no máximo a cada 15 s, e na hora quando forçado', () {
    final h = history();
    h.opened('aaaaaaaaaaa', 'auto');
    h.update('aaaaaaaaaaa', pos: 42, dur: 600);
    h.save(force: false);
    expect(History(file()).find('aaaaaaaaaaa')!.pos, 0); // acabou de gravar ao abrir

    now = now.add(const Duration(seconds: 16));
    h.save(force: false);
    expect(History(file()).find('aaaaaaaaaaa')!.pos, 42);

    h.update('aaaaaaaaaaa', pos: 50);
    h.save();
    final reread = History(file()).find('aaaaaaaaaaa')!;
    expect(reread.pos, 50);
    expect(reread.dur, 600);
    expect(reread.resumeAt, 50);
  });

  test('lê o historico.json do app.py e ignora o que estiver estragado', () {
    file().writeAsStringSync(jsonEncode([
      {
        'id': 'UF8uR6Z6KLc',
        'url': 'https://www.youtube.com/watch?v=UF8uR6Z6KLc',
        'source': 'auto',
        'at': 1763200000,
        'title': "Steve Jobs' 2005 Stanford Commencement Address",
        'author': 'Stanford',
        'pos': 595.5,
        'dur': 904.2,
      },
      {'id': 'curto'},
      'lixo',
      {'id': 'jNQXAC9IVRw', 'source': 'xx'},
    ]));
    final h = history();
    expect(ids(h), ['UF8uR6Z6KLc', 'jNQXAC9IVRw']);
    expect(h.items.first.author, 'Stanford');
    expect(h.items.last.source, 'auto');

    file().writeAsStringSync('{não é json');
    expect(history().isEmpty, isTrue);
  });

  test('resumeAt: não retoma no começo nem no fim', () {
    expect(HistoryItem(id: 'aaaaaaaaaaa', pos: 3, dur: 100).resumeAt, 0);
    expect(HistoryItem(id: 'aaaaaaaaaaa', pos: 95, dur: 100).resumeAt, 0);
    expect(HistoryItem(id: 'aaaaaaaaaaa', pos: 50, dur: 100).resumeAt, 50);
  });

  test('preferências: só subSize e show, com valores válidos', () {
    final f = File('${dir.path}/preferencias.json');
    final p = Prefs(f);
    expect(p.subSize, Prefs.defaultSubSize);
    expect(p.show, ShowMode.both);
    p.subSize = 100;
    p.show = ShowMode.translation;
    p.set('outra', 1);
    p.set('subSize', true);
    expect(jsonDecode(f.readAsStringSync()), {'subSize': Prefs.maxSubSize, 'show': 'tr'});
    expect(Prefs(f).show, ShowMode.translation);
  });
}
