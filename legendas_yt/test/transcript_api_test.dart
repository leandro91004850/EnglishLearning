import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:legendas_yt/src/core/subtitles.dart';
import 'package:legendas_yt/src/youtube/transcript_api.dart';

import 'helpers.dart';

void main() {
  const vid = 'abcdefghijk';

  group('list', () {
    test('feitas por pessoas primeiro, depois as automáticas, sem &fmt=srv3', () async {
      final yt = FakeYouTube(
        player: playerResponse(tracks: [
          captionTrack('en', asr: true),
          captionTrack('pt-BR', name: 'Portuguese (Brazil)'),
          captionTrack('en', name: 'English'),
        ]),
      );
      final tracks = await TranscriptApi(client: yt.client).list(vid);
      expect(tracks.map((t) => '$t'), ['pt-BR', 'en', 'en(auto)']);
      expect(tracks[0].language, 'Portuguese (Brazil)');
      expect(tracks[2].language, 'en (auto-generated)');
      expect(tracks.every((t) => !t.url.contains('fmt=srv3')), isTrue);
    });

    test('pede como o app de Android, em inglês, com os cookies da página', () async {
      final yt = FakeYouTube();
      await TranscriptApi(client: yt.client).list(vid);
      final watch = yt.requests[0];
      final player = yt.requests[1];
      expect(watch.url.toString(), 'https://www.youtube.com/watch?v=$vid');
      expect(watch.headers['Accept-Language'], 'en-US');
      expect(player.url.queryParameters['key'], fakeApiKey);
      expect(jsonDecode(player.body), {
        'context': {
          'client': {'clientName': 'ANDROID', 'clientVersion': '20.10.38'},
        },
        'videoId': vid,
      });
      expect(player.headers['Cookie'], 'YSC=abc123; VISITOR_INFO1_LIVE=xyz');
    });

    test('aceita o aviso de cookies e tenta de novo', () async {
      final yt = FakeYouTube()..consentUntilCookie = true;
      final tracks = await TranscriptApi(client: yt.client).list(vid);
      expect(tracks, hasLength(1));
      expect(yt.requests[1].headers['Cookie'], contains('CONSENT=YES+cb.20261115-07-p0.pt+FX+917'));
    });

    test('aviso de cookies que não some vira FailedToCreateConsentCookie', () async {
      final yt = FakeYouTube(watch: consentPage);
      await expectLater(TranscriptApi(client: yt.client).list(vid), throwsA(isA<FailedToCreateConsentCookie>()));
    });

    test('página com captcha vira IpBlocked; sem a chave, YouTubeDataUnparsable', () async {
      await expectLater(
        TranscriptApi(client: FakeYouTube(watch: '<div class="g-recaptcha"></div>').client).list(vid),
        throwsA(isA<IpBlocked>()),
      );
      await expectLater(
        TranscriptApi(client: FakeYouTube(watch: '<html></html>').client).list(vid),
        throwsA(isA<YouTubeDataUnparsable>()),
      );
    });

    test('HTTP 429 vira IpBlocked; outros erros HTTP, YouTubeRequestFailed', () async {
      await expectLater(
        TranscriptApi(client: (FakeYouTube()..watchStatus = 429).client).list(vid),
        throwsA(isA<IpBlocked>()),
      );
      await expectLater(
        TranscriptApi(client: (FakeYouTube()..playerStatus = 500).client).list(vid),
        throwsA(isA<YouTubeRequestFailed>().having((e) => e.statusCode, 'status', 500)),
      );
    });

    test('playabilityStatus', () async {
      Future<Object?> errorFor(Map<String, Object?> status) async {
        try {
          await TranscriptApi(client: FakeYouTube(player: playerResponse(status: status)).client).list(vid);
        } catch (e) {
          return e;
        }
        return null;
      }

      final bot = await errorFor({'status': 'LOGIN_REQUIRED', 'reason': 'Sign in to confirm you’re not a bot'});
      expect(bot, isA<RequestBlocked>());
      expect(bot, isNot(isA<IpBlocked>()));
      expect(
        await errorFor({'status': 'LOGIN_REQUIRED', 'reason': 'This video may be inappropriate for some users.'}),
        isA<AgeRestricted>(),
      );
      expect(await errorFor({'status': 'ERROR', 'reason': 'This video is unavailable'}), isA<VideoUnavailable>());
      final unplayable = await errorFor({
        'status': 'UNPLAYABLE',
        'reason': 'Video unavailable',
        'errorScreen': {
          'playerErrorMessageRenderer': {
            'subreason': {
              'runs': [
                {'text': 'The uploader has not made this video available in your country'},
              ],
            },
          },
        },
      });
      expect(unplayable, isA<VideoUnplayable>());
      unplayable as VideoUnplayable;
      expect(unplayable.reason, 'Video unavailable');
      expect(unplayable.subreasons, ['The uploader has not made this video available in your country']);
    });

    test('sem captionTracks vira TranscriptsDisabled', () async {
      final yt = FakeYouTube(player: playerResponse());
      await expectLater(TranscriptApi(client: yt.client).list(vid), throwsA(isA<TranscriptsDisabled>()));
    });

    test('sem conexão vira TranscriptNetworkError', () async {
      final client = MockClient((_) async => throw http.ClientException('offline'));
      await expectLater(TranscriptApi(client: client).list(vid), throwsA(isA<TranscriptNetworkError>()));
    });
  });

  group('fetch', () {
    test('lê o XML: entidades escapadas duas vezes, tags e falas sem texto', () async {
      final yt = FakeYouTube(
        xml: '<?xml version="1.0" encoding="utf-8" ?><transcript>'
            '<text start="0.5" dur="1.25">I&amp;#39;m here &amp;amp; there</text>'
            '<text start="2" dur="1"></text>'
            '<text start="3.1">&lt;font color=&quot;#E5E5E5&quot;&gt;so&lt;/font&gt; cool</text>'
            '<text start="4" dur="2"/>'
            '</transcript>',
      );
      final api = TranscriptApi(client: yt.client);
      final cues = await api.fetch((await api.list(vid)).single);
      expect(cues.map((c) => c.text), ["I'm here & there", 'so cool']);
      expect(cues[0].start, 0.5);
      expect(cues[0].dur, 1.25);
      expect(cues[1].dur, 0);
    });

    test('faixa que pede PoToken', () async {
      final yt = FakeYouTube(player: playerResponse(tracks: [captionTrack('en', extra: '&exp=xpe')]));
      final api = TranscriptApi(client: yt.client);
      final track = (await api.list(vid)).single;
      await expectLater(api.fetch(track), throwsA(isA<PoTokenRequired>()));
    });

    test('formato srv3 (milissegundos)', () {
      final cues = parseTranscript(
        '<timedtext format="3"><body><p t="1500" d="2000"><s>Hello</s><s> world</s></p>'
        '<p t="4000" d="500">\n</p></body></timedtext>',
      );
      expect(cues, hasLength(1));
      expect(cues.single.start, 1.5);
      expect(cues.single.dur, 2);
      expect(cues.single.text, 'Hello world');
    });
  });

  test('friendlyError (mensagens do app.py)', () {
    expect(friendlyError(const TranscriptsDisabled(vid)), 'Este vídeo não tem legendas (nem automáticas).');
    expect(friendlyError(const IpBlocked(vid)), startsWith('O YouTube bloqueou temporariamente'));
    expect(friendlyError(const PoTokenRequired(vid)), 'Erro ao buscar legendas: PoTokenRequired');
  });
}
