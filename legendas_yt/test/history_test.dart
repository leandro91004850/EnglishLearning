import 'package:flutter_test/flutter_test.dart';
import 'package:legendas_yt/src/data/history.dart';
import 'package:legendas_yt/src/data/prefs.dart';

import 'fake_api.dart';

void main() {
  late FakeApi fake;
  late DateTime now;
  History history() => History(fake.api(), now: () => now);
  List<String> ids(History h) => [for (final x in h.items) x.id];

  setUp(() {
    fake = FakeApi();
    now = DateTime(2026, 11, 21, 10);
  });

  test('a lista vem da API, com todos os vídeos; o que estiver estragado fica de fora', () async {
    fake.videos = [
      video('UF8uR6Z6KLc', title: 'Steve Jobs', pos: 595.5, dur: 904.2),
      {'id': 'curto'},
      {'id': 'jNQXAC9IVRw', 'source': 'xx'},
    ];
    final h = history();
    expect(await h.load(), isEmpty);
    expect(h.loaded, isTrue);
    expect(ids(h), ['UF8uR6Z6KLc', 'jNQXAC9IVRw']);
    expect(h.items.first.resumeAt, 595.5);
    expect(h.items.last.source, 'auto');

    fake.dbMessage = 'Sem conexão com o PostgreSQL em db:5432.';
    expect(await h.load(), fake.dbMessage, reason: 'o banco da API com problema');
    fake.down = true;
    expect(await h.load(), startsWith('Sem conexão com a API'));
    expect(ids(h), ['UF8uR6Z6KLc', 'jNQXAC9IVRw'], reason: 'sem resposta, a lista fica como estava');
  });

  test('link novo entra no topo; aberto pela lista fica no lugar', () async {
    fake.videos = [video('bbbbbbbbbbb'), video('ccccccccccc')];
    final h = history();
    await h.load();
    h.opened('aaaaaaaaaaa', 'auto');
    expect(ids(h), ['aaaaaaaaaaa', 'bbbbbbbbbbb', 'ccccccccccc']);
    h.opened('ccccccccccc', 'pt', keepPlace: true);
    expect(ids(h), ['aaaaaaaaaaa', 'bbbbbbbbbbb', 'ccccccccccc']);
    expect(h.find('ccccccccccc')!.source, 'pt');
    h.opened('bbbbbbbbbbb', 'auto'); // colado de novo: sobe
    expect(ids(h).first, 'bbbbbbbbbbb');
    h.opened('ddddddddddd', 'auto', keepPlace: true);
    h.opened('eeeeeeeeeee', 'auto', restoring: true);
    expect(ids(h), ['bbbbbbbbbbb', 'aaaaaaaaaaa', 'ccccccccccc'], reason: 'nem um nem outro entram');
    expect(fake.paths, ['GET /recentes'], reason: 'quem grava a abertura é a API, em /abrir');
  });

  test('arrastar muda a ordem e manda para a API; o último assistido', () async {
    fake.videos = [
      video('aaaaaaaaaaa', at: 1),
      video('bbbbbbbbbbb', at: 3),
      video('ccccccccccc', at: 2),
    ];
    final h = history();
    await h.load();
    expect(h.latest!.id, 'bbbbbbbbbbb');
    expect(h.reorder(0, 2), isTrue);
    expect(ids(h), ['bbbbbbbbbbb', 'ccccccccccc', 'aaaaaaaaaaa']);
    expect(h.move('aaaaaaaaaaa', -1), isTrue);
    expect(h.reorder(1, 1), isFalse);
    expect(h.reorder(9, 0), isFalse);
    expect(await h.flush(), isTrue);
    expect(fake.orders, [
      ['bbbbbbbbbbb', 'aaaaaaaaaaa', 'ccccccccccc'],
    ], reason: 'vai a ordem mais nova, uma vez só');
    h.reorder(0, 2);
    h.reorder(2, 0); // voltou ao que a API já tem: nada a mandar
    await h.flush();
    expect(fake.orders, hasLength(1));
    expect(h.latest!.id, 'bbbbbbbbbbb', reason: 'mover não muda o `at`');
  });

  test('posição: vai para a API no máximo a cada 15 s, e na hora quando forçado', () async {
    fake.videos = [video('aaaaaaaaaaa')];
    final h = history();
    await h.load();
    h.update('aaaaaaaaaaa', pos: 42, dur: 600);
    h.save(force: false); // a primeira vai
    await h.flush();
    expect(fake.positions, [('aaaaaaaaaaa', 42.0, 600.0)]);

    h.update('aaaaaaaaaaa', pos: 50, dur: 600);
    h.save(force: false);
    await pumpEventQueue();
    expect(fake.positions, hasLength(1), reason: 'menos de 15 s depois');
    now = now.add(const Duration(seconds: 16));
    h.save(force: false);
    await h.flush();
    expect(fake.positions.last, ('aaaaaaaaaaa', 50.0, 600.0));

    // API fora do ar: fica para o próximo envio
    fake.down = true;
    h.update('aaaaaaaaaaa', pos: 60);
    await h.flush();
    fake.down = false;
    await h.flush();
    expect(fake.positions.last, ('aaaaaaaaaaa', 60.0, 600.0));
    expect(h.find('aaaaaaaaaaa')!.resumeAt, 60);
  });

  test('resumeAt: não retoma no começo nem no fim', () {
    expect(HistoryItem(id: 'aaaaaaaaaaa', pos: 3, dur: 100).resumeAt, 0);
    expect(HistoryItem(id: 'aaaaaaaaaaa', pos: 95, dur: 100).resumeAt, 0);
    expect(HistoryItem(id: 'aaaaaaaaaaa', pos: 50, dur: 100).resumeAt, 50);
  });

  test('preferências: vêm da API, só subSize e show; cada mudança vai na hora', () async {
    fake.prefs = {'subSize': 30, 'show': 'tr', 'outra': 1};
    final p = Prefs(fake.api());
    expect(p.subSize, Prefs.defaultSubSize);
    await p.load();
    expect((p.subSize, p.show), (30, ShowMode.translation));
    expect(p.all.keys, ['subSize', 'show']);
    p.subSize = 100;
    p.set('outra', 2);
    p.set('show', true);
    await pumpEventQueue();
    expect(fake.prefs['subSize'], Prefs.maxSubSize);
    expect(fake.prefs['outra'], 1, reason: 'chave desconhecida não vai');

    // mudada nesta sessão antes de ler a API: fica
    final q = Prefs(fake.api())..show = ShowMode.original;
    await q.load();
    expect(q.show, ShowMode.original);
  });
}
