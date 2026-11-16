import 'package:flutter_test/flutter_test.dart';
import 'package:legendas_yt/src/core/cue.dart';
import 'package:legendas_yt/src/core/subtitles.dart';
import 'package:legendas_yt/src/core/text.dart';
import 'package:legendas_yt/src/youtube/transcript_api.dart';
import 'package:legendas_yt/src/youtube/video_id.dart';

CaptionTrack track(String code, {bool auto = false, String? name}) => CaptionTrack(
      videoId: 'abcdefghijk',
      url: 'https://www.youtube.com/api/timedtext?lang=$code',
      language: name ?? code,
      languageCode: code,
      isGenerated: auto,
    );

void main() {
  test('extractVideoId', () {
    expect(extractVideoId('UF8uR6Z6KLc'), 'UF8uR6Z6KLc');
    expect(extractVideoId(' https://www.youtube.com/watch?v=UF8uR6Z6KLc&t=30 '), 'UF8uR6Z6KLc');
    expect(extractVideoId('https://youtu.be/UF8uR6Z6KLc?si=abc'), 'UF8uR6Z6KLc');
    expect(extractVideoId('https://www.youtube.com/shorts/UF8uR6Z6KLc'), 'UF8uR6Z6KLc');
    expect(extractVideoId('https://www.youtube.com/embed/UF8uR6Z6KLc'), 'UF8uR6Z6KLc');
    expect(extractVideoId('https://www.youtube.com/live/UF8uR6Z6KLc'), 'UF8uR6Z6KLc');
    expect(extractVideoId('https://m.youtube.com/watch?feature=share&v=UF8uR6Z6KLc'), 'UF8uR6Z6KLc');
    expect(extractVideoId('https://example.com/video'), isNull);
    expect(extractVideoId(''), isNull);
  });

  test('startTimeFromUrl', () {
    expect(startTimeFromUrl('https://youtu.be/UF8uR6Z6KLc?t=90'), 90);
    expect(startTimeFromUrl('https://www.youtube.com/watch?v=UF8uR6Z6KLc&t=1m30s'), 90);
    expect(startTimeFromUrl('https://www.youtube.com/watch?v=UF8uR6Z6KLc&t=1h2m3s'), 3723);
    expect(startTimeFromUrl('https://www.youtube.com/watch?v=UF8uR6Z6KLc'), isNull);
  });

  test('pickTranscript', () {
    final enAuto = track('en', auto: true), ptAuto = track('pt', auto: true);
    final en = track('en'), pt = track('pt-BR'), es = track('es');
    // auto: feita por pessoas ganha da automática, EN antes de PT
    expect(pickTranscript([pt, en, enAuto], 'auto', 'x'), en);
    expect(pickTranscript([pt, enAuto], 'auto', 'x'), pt);
    expect(pickTranscript([es, enAuto], 'auto', 'x'), enAuto);
    expect(pickTranscript([es], 'auto', 'x'), es);
    // en/pt: o idioma pedido, mesmo automático
    expect(pickTranscript([en, ptAuto], 'pt', 'x'), ptAuto);
    expect(pickTranscript([pt, enAuto], 'en', 'x'), enAuto);
    expect(() => pickTranscript([], 'auto', 'x'), throwsA(isA<NoTranscriptFound>()));
  });

  test('idiomas', () {
    expect(langFamily('pt-BR'), 'pt');
    expect(targetFor('pt-BR'), 'en');
    expect(targetFor('en-US'), 'pt');
    expect(targetFor('es-419'), 'pt');
    expect(languageName(track('en', name: 'English (auto-generated)')), 'English');
    expect(languageName(track('pt-BR', name: 'Portuguese (Brazil) (auto-generated)')), 'Portuguese');
    expect(languageName(track('ja', name: '')), 'ja');
    expect(languageName(track('en', name: 'English - English')), 'English');
    expect(languageName(track('en', name: 'English - CC1')), 'English - CC1');
  });

  test('makeChunks: até 1200 caracteres ou 40 falas', () {
    final short = [for (var i = 0; i < 100; i++) (i, 'abc')];
    expect(makeChunks(short).map((c) => c.length), [40, 40, 20]);
    final long = [for (var i = 0; i < 5; i++) (i, 'x' * 500)];
    expect(makeChunks(long).map((c) => c.length), [2, 2, 1]);
    expect(makeChunks([]), isEmpty);
  });

  test('cueIndexAt', () {
    const cues = [Cue(1, 2, 'a'), Cue(3, 2, 'b'), Cue(10, 1, 'c')];
    expect(cueIndexAt(cues, 0.5), -1);
    expect(cueIndexAt(cues, 0.96), 0); // margem de 50 ms
    expect(cueIndexAt(cues, 4), 1);
    expect(cueIndexAt(cues, 7), 1);
    expect(cueIndexAt(cues, 99), 2);
    expect(cueIndexAt(const [], 3), -1);
  });

  test('texto', () {
    expect(clean('  a \n b\t c '), 'a b c');
    expect(oneLine('​olá﻿ mundo'), 'olá mundo');
    expect(unescapeHtml('I&#39;m &quot;ok&quot; &amp; &#x263A; &eacute; &bogus;'), 'I\'m "ok" & ☺ é &bogus;');
    expect(formatTime(75), '1:15');
    expect(formatTime(3725), '1:02:05');
    expect(formatTime(double.nan), '0:00');
    expect(thousands(5000), '5.000');
    expect(thousands(1234567), '1.234.567');
    expect(thousands(12), '12');
  });
}
