import 'package:flutter_test/flutter_test.dart';
import 'package:legendas_yt/src/core/cue.dart';
import 'package:legendas_yt/src/core/text.dart';
import 'package:legendas_yt/src/youtube/video_id.dart';

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
