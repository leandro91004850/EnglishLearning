import 'package:legendas_yt/src/core/subtitles.dart';
import 'package:legendas_yt/src/data/banco.dart';

/// Um banco de mentira no nível das operações (recentes, preferências, legendas).
/// `down = true` simula o servidor fora do ar.
class FakeBanco extends Banco {
  FakeBanco() : super(null, connect: () async => throw UnimplementedError('sem SQL nos testes'));

  bool down = false;
  List<Map<String, Object?>> recent = [];
  final List<List<String>> savedLists = [];

  /// Vídeos da tabela videos que estão fora da lista (cortados pelo limite de 30
  /// de uma versão antiga, ou tirados com × no app Python): entram no fim dela em
  /// [addMissingVideos].
  List<Map<String, Object?>> outOfList = [];

  /// Os vídeos de cada gravação só de posição e título ([updateRecent]).
  final List<List<String>> updatedRows = [];
  Map<String, Object?> prefs = {};
  final List<(String, Object)> savedPrefs = [];

  SavedTrack? stored; // a legenda que o banco já tem
  final List<String> calls = [];
  final List<(int, String)> translationsSaved = [];

  @override
  Future<List<Map<String, Object?>>?> loadRecent() async =>
      down ? null : [for (final x in recent) Map<String, Object?>.of(x)];

  @override
  Future<bool> saveRecent(List<Map<String, Object?>> items) async {
    if (down) return false;
    savedLists.add([for (final x in items) x['id']! as String]);
    // quem saiu da lista continua na tabela videos
    final kept = {for (final x in items) x['id']};
    outOfList = [
      for (final x in [...recent, ...outOfList])
        if (!kept.contains(x['id'])) x,
    ];
    recent = [for (final x in items) Map<String, Object?>.of(x)];
    return true;
  }


  @override
  Future<bool> updateRecent(List<Map<String, Object?>> items) async {
    if (down) return false;
    updatedRows.add([for (final x in items) x['id']! as String]);
    return true;
  }

  @override
  Future<int> addMissingVideos() async {
    if (down) return 0;
    final back = outOfList;
    outOfList = [];
    recent = [...recent, for (final x in back) Map<String, Object?>.of(x)];
    return back.length;
  }

  @override
  Future<Map<String, Object?>?> loadPrefs() async => down ? null : Map.of(prefs);

  @override
  Future<bool> savePref(String key, Object value) async {
    if (down) return false;
    savedPrefs.add((key, value));
    prefs[key] = value;
    return true;
  }

  @override
  Future<SavedTrack?> findTranscript(String vid, String choice, {bool wait = true}) async {
    calls.add('findTranscript');
    return down ? null : stored;
  }

  @override
  Future<SavedTrack?> findTrack(String vid, String code, bool generated, {bool wait = true}) async {
    calls.add('findTrack');
    return null;
  }

  @override
  Future<bool> linkChoice(String vid, String choice, SavedTrack saved) async {
    calls.add('linkChoice');
    return true;
  }

  @override
  Future<void> saveTranscript(SavedTrack saved, String vid, String choice) async {
    calls.add('saveTranscript $vid $choice ${saved.meta.cues.length}');
    saved.id = 7;
    saved.db = generation;
  }

  @override
  Future<void> saveTranslations(SavedTrack saved, List<(int, String)> pairs) async {
    calls.add('saveTranslations ${saved.id}');
    translationsSaved.addAll(pairs);
  }

  @override
  Future<void> storeComplete(String vid, String choice, SubtitleMeta meta, List<(int, String)> pairs) async {
    calls.add('storeComplete $vid ${pairs.length}');
  }
}
