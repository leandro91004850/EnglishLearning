import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legendas_yt/src/data/history.dart';
import 'package:legendas_yt/src/data/prefs.dart';

import 'fake_banco.dart';

void main() {
  late Directory dir;
  late FakeBanco db;
  File historyFile() => File('${dir.path}/historico.json');
  File syncFile() => File('${dir.path}/historico-banco.json');

  Map<String, Object?> item(String id, {int at = 1763200000}) => {'id': id, 'source': 'auto', 'at': at};

  /// Recentes salvos no aparelho, e se eles estavam em dia com o banco.
  History localHistory(List<String> ids, {bool synced = false}) {
    historyFile().writeAsStringSync(jsonEncode([for (final id in ids) item(id)]));
    if (synced) syncFile().writeAsStringSync(jsonEncode({'sincronizado': true}));
    return History(historyFile())..attach(db);
  }

  List<String> ids(History h) => [for (final x in h.items) x.id];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('legendas_sync');
    db = FakeBanco();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('Recentes e o banco', () {
    test('primeira vez com o banco: a lista do aparelho vai por cima e é gravada', () async {
      db.recent = [item('ccccccccccc'), item('aaaaaaaaaaa')];
      final h = localHistory(['aaaaaaaaaaa', 'bbbbbbbbbbb']);
      expect(await h.loadFromDb(), isTrue);
      expect(ids(h), ['aaaaaaaaaaa', 'bbbbbbbbbbb', 'ccccccccccc']);
      h.save();
      await db.flush();
      expect(db.savedLists.last, ['aaaaaaaaaaa', 'bbbbbbbbbbb', 'ccccccccccc']);
      expect(jsonDecode(syncFile().readAsStringSync()), {'sincronizado': true});
      // e o aparelho guarda a lista junta
      expect([for (final x in jsonDecode(historyFile().readAsStringSync()) as List) x['id']], ids(h));
    });

    test('aparelho em dia: vale a lista do banco (mudou no computador)', () async {
      db.recent = [item('ccccccccccc'), item('bbbbbbbbbbb')];
      final h = localHistory(['aaaaaaaaaaa', 'bbbbbbbbbbb'], synced: true);
      await h.loadFromDb();
      expect(ids(h), ['ccccccccccc', 'bbbbbbbbbbb']);
      h.save();
      await db.flush();
      expect(db.savedLists, isEmpty, reason: 'nada mudou no aparelho');
    });

    test('vídeo aberto antes de o banco responder fica no topo', () async {
      db.recent = [item('ccccccccccc'), item('bbbbbbbbbbb')];
      final h = localHistory(['aaaaaaaaaaa', 'bbbbbbbbbbb'], synced: true);
      h.opened('ddddddddddd', 'en');
      await h.loadFromDb();
      expect(ids(h), ['ddddddddddd', 'ccccccccccc', 'bbbbbbbbbbb']);
      h.save();
      await db.flush();
      expect(db.savedLists.last, ['ddddddddddd', 'ccccccccccc', 'bbbbbbbbbbb']);
    });

    test('reabrir o último vídeo ao iniciar não conta como mudança', () async {
      db.recent = [item('ccccccccccc'), item('bbbbbbbbbbb')];
      final h = localHistory(['aaaaaaaaaaa', 'bbbbbbbbbbb'], synced: true);
      h.opened('aaaaaaaaaaa', 'auto', keepPlace: true, restoring: true);
      await h.loadFromDb();
      expect(ids(h), ['ccccccccccc', 'bbbbbbbbbbb']);
    });

    test('banco fora do ar: guarda no aparelho e junta quando ele volta', () async {
      db.down = true;
      db.recent = [item('ccccccccccc')];
      final h = localHistory(['aaaaaaaaaaa'], synced: true);
      expect(await h.loadFromDb(), isFalse);
      h.opened('eeeeeeeeeee', 'auto');
      await db.flush();
      expect(db.savedLists, isEmpty);
      expect(History(historyFile()).items.first.id, 'eeeeeeeeeee', reason: 'ficou no aparelho');
      expect(jsonDecode(syncFile().readAsStringSync()), {'sincronizado': false});

      db.down = false;
      h.save();
      await db.flush();
      expect(db.savedLists.last, ['eeeeeeeeeee', 'ccccccccccc']);
    });

    test('mudança fora do ar sobrevive a reabrir o app', () async {
      db.down = true;
      final h = localHistory(['aaaaaaaaaaa', 'bbbbbbbbbbb'], synced: true);
      h.reorder(1, 0);
      await db.flush();

      db.down = false;
      db.recent = [item('aaaaaaaaaaa'), item('bbbbbbbbbbb'), item('ccccccccccc')];
      final reopened = History(historyFile())..attach(db);
      await reopened.loadFromDb();
      expect(ids(reopened), ['bbbbbbbbbbb', 'aaaaaaaaaaa', 'ccccccccccc']);
    });

    test('sem limite: todos os vídeos do banco vêm para a lista', () async {
      db.recent = [for (var i = 0; i < 45; i++) item('v${i.toString().padLeft(10, '0')}')];
      final h = localHistory([], synced: true);
      await h.loadFromDb();
      expect(h.items, hasLength(45));
      expect(History(historyFile()).items, hasLength(45), reason: 'a cópia no aparelho também tem todos');
    });

    test('os vídeos do banco que estavam fora da lista entram nela, no fim, a cada leitura', () async {
      db.recent = [item('aaaaaaaaaaa'), item('bbbbbbbbbbb')];
      db.outOfList = [item('xxxxxxxxxxx'), item('yyyyyyyyyyy')];
      final h = localHistory(['aaaaaaaaaaa', 'bbbbbbbbbbb'], synced: true);
      await h.loadFromDb();
      expect(ids(h), ['aaaaaaaaaaa', 'bbbbbbbbbbb', 'xxxxxxxxxxx', 'yyyyyyyyyyy']);
      expect(h.canRemove, isFalse, reason: 'com o banco, a lista não tem ×');

      // uma versão antiga cortou a lista de novo: na próxima leitura o vídeo volta
      db.recent.removeLast();
      db.outOfList = [item('yyyyyyyyyyy')];
      final again = History(historyFile())..attach(db);
      await again.loadFromDb();
      expect(ids(again), ['aaaaaaaaaaa', 'bbbbbbbbbbb', 'xxxxxxxxxxx', 'yyyyyyyyyyy']);
    });
    test('posição e título: grava só a linha do vídeo, sem regravar a lista', () async {
      db.recent = [item('aaaaaaaaaaa'), item('bbbbbbbbbbb')];
      final h = localHistory(['aaaaaaaaaaa', 'bbbbbbbbbbb'], synced: true);
      await h.loadFromDb();
      h.update('bbbbbbbbbbb', pos: 42, dur: 600);
      h.save();
      await db.flush();
      expect(db.updatedRows, [
        ['bbbbbbbbbbb'],
      ]);
      expect(db.savedLists, isEmpty);

      // a lista mudou: vai inteira, com a posição junto
      h.update('aaaaaaaaaaa', pos: 7);
      h.reorder(1, 0);
      await db.flush();
      expect(db.updatedRows, hasLength(1));
      expect(db.savedLists.last, ['bbbbbbbbbbb', 'aaaaaaaaaaa']);
    });

    test('posição com o banco fora do ar: grava quando ele volta', () async {
      db.recent = [item('aaaaaaaaaaa')];
      final h = localHistory(['aaaaaaaaaaa'], synced: true);
      await h.loadFromDb();
      db.down = true;
      h.update('aaaaaaaaaaa', pos: 42);
      h.save();
      await db.flush();
      expect(db.updatedRows, isEmpty);

      db.down = false;
      h.save();
      await db.flush();
      expect(db.updatedRows, [
        ['aaaaaaaaaaa'],
      ]);
      expect(db.savedLists, isEmpty);
    });

    test('arrastar depois de ler o banco grava a nova ordem', () async {
      db.recent = [item('aaaaaaaaaaa'), item('bbbbbbbbbbb')];
      final h = localHistory([], synced: true);
      await h.loadFromDb();
      h.reorder(0, 1);
      await db.flush();
      expect(db.savedLists.last, ['bbbbbbbbbbb', 'aaaaaaaaaaa']);
    });
  });

  group('Preferências e o banco', () {
    test('valem as do banco; as que só o aparelho tem vão para o banco', () async {
      final f = File('${dir.path}/preferencias.json')..writeAsStringSync(jsonEncode({'subSize': 30}));
      db.prefs = {'show': 'tr'};
      final p = Prefs(f)..attach(db);
      await p.loadFromDb();
      await db.flush();
      expect(p.show, ShowMode.translation);
      expect(p.subSize, 30);
      expect(db.savedPrefs, [('subSize', 30)]);
      expect(jsonDecode(f.readAsStringSync()), {'subSize': 30, 'show': 'tr'});
    });

    test('mudada nesta sessão antes de ler o banco fica', () async {
      db.prefs = {'show': 'tr', 'subSize': 20};
      final p = Prefs(File('${dir.path}/preferencias.json'))..attach(db);
      p.show = ShowMode.original;
      await p.loadFromDb();
      await db.flush();
      expect(p.show, ShowMode.original);
      expect(p.subSize, 20);
      expect(db.savedPrefs, contains(('show', 'orig')));
    });
  });
}
