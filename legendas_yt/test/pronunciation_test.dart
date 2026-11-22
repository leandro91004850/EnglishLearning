import 'package:flutter_test/flutter_test.dart';
import 'package:legendas_yt/src/quiz/pronunciation.dart';

void main() {
  List<bool> marks(SpeechCheck check) => [for (final w in check.words) w.heard];

  test('a frase dita certinho passa, sem contar maiúsculas e pontuação', () {
    final check = SpeechCheck.of("Lost in love and I don't know much", "lost in love and i don't know much");
    expect((check.score, check.passed, check.percent), (1.0, true, 100));
    expect(marks(check), everyElement(isTrue));
  });

  test('contrações, formas da fala, números e palavras que soam igual', () {
    expect(SpeechCheck.of("I'm gonna miss you", 'I am going to miss you').score, 1);
    expect(SpeechCheck.of("Nothin' compares to you", 'nothing compares to you').score, 1);
    expect(SpeechCheck.of('I need you too', 'I need you 2').score, 1);
    expect(SpeechCheck.of('Over there', 'over their').score, 1);
    expect(SpeechCheck.of("It's my life", 'it is my life').score, 1);
    expect(SpeechCheck.of("Don't you know", 'dont you no').score, 1);
    expect(SpeechCheck.of('My favourite song', 'my favorite song').score, 1, reason: 'grafia, palavra longa');
  });

  test('palavra que faltou fica marcada; passa com 75% da frase', () {
    final check = SpeechCheck.of('What the hell am I doing here?', 'what the hell am I doing');
    expect(check.passed, isTrue);
    expect(check.percent, 86);
    expect(marks(check), [true, true, true, true, true, true, false]);
  });

  test('outra coisa não passa, e palavra curta trocada não vale', () {
    final check = SpeechCheck.of('I promise you', "I'm a nice view");
    expect(check.passed, isFalse);
    expect(marks(check), [true, false, false]);
    expect(SpeechCheck.of('I want you', 'I went you').passed, isFalse, reason: 'want ≠ went');
    expect(SpeechCheck.of('I love you', '').score, 0);
  });

  test('interjeições das músicas não contam, a não ser numa frase só delas', () {
    final check = SpeechCheck.of('Oh, I love you', 'I love you');
    expect(check.score, 1);
    expect(marks(check), [true, true, true, true]);
    expect(SpeechCheck.of('Oh oh oh', '').score, 0);
    expect(SpeechCheck.of('Oh oh oh', 'oh oh oh').score, 1);
  });

  test('palavras a mais não atrapalham; vale a transcrição mais parecida', () {
    expect(SpeechCheck.of('I love you', 'yeah I love you so much').score, 1);
    final best = SpeechCheck.best('I love you', ['I loved you', 'I love you']);
    expect((best.score, best.heard), (1.0, 'I love you'));
    expect(SpeechCheck.best('I love you', []).score, 0);
  });

  test('as palavras na forma de comparar', () {
    expect(speechTokens("Don't"), ['do', 'not']);
    expect(speechTokens("John's car"), ['johns', 'car']);
    expect(speechTokens("rock 'n' roll"), ['rock', 'and', 'roll']);
    expect(speechTokens('twenty-one'), speechTokens('21'));
    expect(speechTokens('“Hello,” she said...'), ['hello', 'she', 'said']);
  });
}
