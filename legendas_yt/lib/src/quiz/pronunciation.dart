/// Confere a pronúncia nas lições: compara o que o reconhecimento de voz do aparelho ouviu com a
/// frase, palavra por palavra.
///
/// O reconhecimento de voz devolve texto, então "pronúncia certa" aqui é "o aparelho entendeu as
/// palavras da frase". Para não reprovar o que foi bem dito, a comparação ignora maiúsculas e
/// pontuação e aceita:
/// - contrações e formas da fala: "I'm" = "I am", "gonna" = "going to", "nothin'" = "nothing";
/// - números escritos com algarismos: "2" = "two";
/// - palavras que soam igual: "to", "too" e "two"; "there" e "their";
/// - um errinho de grafia nas palavras longas ("favourite" = "favorite").
///
/// Interjeições das músicas ("oh", "ooh", "la la") não contam: o aparelho costuma não escrevê-las.
/// Entre as transcrições que o aparelho achou possíveis, vale a mais parecida com a frase.
library;

import 'dart:math' as math;

/// Uma palavra da frase, como aparece na tela, e se o aparelho a ouviu.
class SpokenWord {
  const SpokenWord(this.text, {required this.heard});

  final String text;
  final bool heard;
}

/// O resultado de uma tentativa de falar a frase.
class SpeechCheck {
  const SpeechCheck({required this.words, required this.score, required this.heard});

  /// Quanto da frase o aparelho precisa ouvir para passar.
  static const double passScore = 0.75;

  /// Confere [phrase] contra as transcrições do aparelho (a mais provável primeiro); vale a que
  /// mais se parece com a frase.
  factory SpeechCheck.best(String phrase, List<String> transcripts) {
    SpeechCheck? best;
    for (final heard in transcripts) {
      final check = SpeechCheck.of(phrase, heard);
      if (best == null || check.score > best.score) best = check;
    }
    return best ?? SpeechCheck.of(phrase, '');
  }

  /// Confere [phrase] contra uma transcrição.
  factory SpeechCheck.of(String phrase, String heard) {
    final shown = phrase.split(' '); // como a tela mostra a frase
    final perWord = [for (final w in shown) speechTokens(w)];
    final want = [for (final t in perWord) ...t];
    final hit = _align(want, speechTokens(heard));

    // as interjeições só contam numa frase que só tem interjeições
    var counted = [for (var i = 0; i < want.length; i++) if (!_fillers.contains(want[i])) i];
    if (counted.isEmpty) counted = [for (var i = 0; i < want.length; i++) i];
    final countedSet = counted.toSet();

    final words = <SpokenWord>[];
    var k = 0;
    for (final (i, text) in shown.indexed) {
      var ok = true;
      for (var j = k; j < k + perWord[i].length; j++) {
        if (countedSet.contains(j) && !hit[j]) ok = false;
      }
      k += perWord[i].length;
      words.add(SpokenWord(text, heard: ok));
    }
    final score = counted.isEmpty ? 0.0 : counted.where((i) => hit[i]).length / counted.length;
    return SpeechCheck(words: words, score: score, heard: heard.trim());
  }

  /// As palavras da frase, separadas por espaço como na tela, marcadas.
  final List<SpokenWord> words;

  /// De 0 a 1: a parte da frase que o aparelho ouviu.
  final double score;

  /// A transcrição usada (a mais parecida com a frase).
  final String heard;

  bool get passed => score >= passScore;

  int get percent => (score * 100).round();
}

/// As palavras de um texto na forma de comparar: minúsculas, sem pontuação, contrações abertas,
/// números por extenso e cada grupo de palavras que soam igual numa forma só.
List<String> speechTokens(String text) {
  final out = <String>[];
  for (final raw in text.toLowerCase().replaceAll(_apostrophes, "'").split(_separators)) {
    var word = raw.replaceAll(_edges, '');
    if (word.isEmpty) continue;
    if (word.length > 4 && word.endsWith("in'") && !word.startsWith("'")) {
      word = '${word.substring(0, word.length - 1)}g'; // nothin' = nothing
    }
    for (final part in _expand(word)) {
      final clean = part.replaceAll(RegExp(r"^'+|'+$"), '');
      if (clean.isEmpty) continue;
      out.add(_soundsLike[clean] ?? clean);
    }
  }
  return out;
}

final RegExp _apostrophes = RegExp('[’‘`´]');
final RegExp _separators = RegExp(r'[\s\-–—/]+');
final RegExp _edges = RegExp(r"^[^\p{L}\p{N}']+|[^\p{L}\p{N}']+$", unicode: true);
final RegExp _digits = RegExp(r'^\d+$');

List<String> _expand(String word) {
  final spoken = _spokenForms[word];
  if (spoken != null) return spoken.split(' ');
  if (_digits.hasMatch(word)) return _number(int.parse(word));
  if (word.endsWith("n't")) return [word.substring(0, word.length - 3), 'not'];
  for (final (end, full) in _endings) {
    if (word.length > end.length && word.endsWith(end)) return [word.substring(0, word.length - end.length), full];
  }
  if (word.endsWith("'s")) {
    final stem = word.substring(0, word.length - 2);
    return _isWords.contains(stem) ? [stem, 'is'] : ['${stem}s']; // it's = it is; John's ~ Johns
  }
  return [word];
}

const List<(String, String)> _endings = [("'m", 'am'), ("'re", 'are'), ("'ve", 'have'), ("'ll", 'will'), ("'d", 'would')];

const Set<String> _isWords = {'it', 'he', 'she', 'that', 'what', 'there', 'here', 'where', 'who', 'how'};

/// Formas da fala (e contrações escritas sem o apóstrofo) -> por extenso.
const Map<String, String> _spokenForms = {
  "can't": 'can not', 'cannot': 'can not', "won't": 'will not', "shan't": 'shall not',
  "ain't": 'aint', "let's": 'let us', "y'all": 'you all', "'n'": 'and', "'n": 'and', "n'": 'and',
  "'cause": 'because', 'cause': 'because', 'cuz': 'because', 'coz': 'because', "'til": 'until',
  'til': 'until', 'till': 'until', "'em": 'them', 'ya': 'you',
  'gonna': 'going to', 'wanna': 'want to', 'gotta': 'got to', 'kinda': 'kind of', 'sorta': 'sort of',
  'outta': 'out of', 'lotta': 'lot of', 'lemme': 'let me', 'gimme': 'give me', 'dunno': 'do not know',
  'dont': 'do not', 'cant': 'can not', 'wont': 'will not', 'didnt': 'did not', 'doesnt': 'does not',
  'isnt': 'is not', 'wasnt': 'was not', 'arent': 'are not', 'werent': 'were not', 'havent': 'have not',
  'hasnt': 'has not', 'couldnt': 'could not', 'wouldnt': 'would not', 'shouldnt': 'should not',
  'im': 'i am', 'ive': 'i have', 'youre': 'you are', 'thats': 'that is', 'whats': 'what is',
};

/// Interjeições: não contam (o aparelho costuma não escrevê-las).
const Set<String> _fillers = {
  'oh', 'ooh', 'ohh', 'ah', 'ahh', 'aah', 'uh', 'uhh', 'um', 'umm', 'hmm', 'mm', 'mmm', 'whoa', 'woah',
  'woo', 'la', 'na', 'da', 'doo', 'ba', 'eh',
};

/// Grupos de palavras que soam igual; cada grupo vira a primeira palavra dele.
const List<String> _sameSound = [
  'to too two', 'there their', 'no know', 'new knew', 'right write', 'hear here', 'for four fore',
  'by buy bye', 'i eye', 'one won', 'see sea', 'be bee', 'meet meat', 'wear where ware',
  'weather whether', 'whole hole', 'our hour', 'son sun', 'wait weight', 'week weak', 'made maid',
  'night knight', 'road rode', 'break brake', 'flower flour', 'piece peace', 'plane plain',
  'sale sail', 'tail tale', 'threw through', 'way weigh', 'would wood', 'ate eight', 'blue blew',
  'dear deer', 'fair fare', 'heal heel', 'hi high', 'mail male', 'pair pear', 'sent cent scent',
  'so sew sow', 'some sum', 'steal steel', 'not knot', 'knows nose', 'seen scene', 'soul sole',
  'roll role', 'rain reign rein', 'him hymn', 'in inn', 'which witch', 'whine wine', 'you u ewe',
  'okay ok', 'allowed aloud', 'bored board', 'sell cell', 'die dye', 'heard herd', 'missed mist',
  'tied tide', 'stair stare', 'all awl',
];

final Map<String, String> _soundsLike = {
  for (final group in _sameSound)
    for (final word in group.split(' ').skip(1)) word: group.split(' ').first,
};

const List<String> _ones = [
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven',
  'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen',
];
const List<String> _tens = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];

List<String> _number(int n) {
  if (n < 20) return [_ones[n]];
  if (n < 100) return [_tens[n ~/ 10], if (n % 10 > 0) _ones[n % 10]];
  if (n < 1000) return [_ones[n ~/ 100], 'hundred', if (n % 100 > 0) ..._number(n % 100)];
  return ['$n'];
}

/// Mesma palavra, ou um errinho de grafia numa palavra longa.
bool _same(String a, String b) => a == b || (a.length >= 6 && b.length >= 6 && _oneEdit(a, b));

bool _oneEdit(String a, String b) {
  if (a == b) return true;
  if ((a.length - b.length).abs() > 1) return false;
  var i = 0;
  while (i < a.length && i < b.length && a[i] == b[i]) {
    i++;
  }
  if (a.length == b.length) return a.substring(i + 1) == b.substring(i + 1); // uma troca
  final (long, short) = a.length > b.length ? (a, b) : (b, a);
  return long.substring(i + 1) == short.substring(i); // uma letra a mais
}

/// Quais palavras da frase ([want]) aparecem no que foi ouvido ([got]), na ordem: a maior
/// sequência em comum. Palavras a mais no que foi ouvido não atrapalham.
List<bool> _align(List<String> want, List<String> got) {
  final n = want.length, m = got.length;
  final best = List.generate(n + 1, (_) => List.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      best[i][j] = _same(want[i], got[j]) ? best[i + 1][j + 1] + 1 : math.max(best[i + 1][j], best[i][j + 1]);
    }
  }
  final hit = List.filled(n, false);
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (_same(want[i], got[j]) && best[i][j] == best[i + 1][j + 1] + 1) {
      hit[i] = true;
      i++;
      j++;
    } else if (best[i + 1][j] >= best[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return hit;
}
