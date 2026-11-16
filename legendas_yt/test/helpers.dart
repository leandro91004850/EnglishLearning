import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const String fakeApiKey = 'AIzaSyFAKE_key-123';

String watchPage() =>
    '<html><script>ytcfg.set({"INNERTUBE_API_KEY": "$fakeApiKey", "X": 1});</script></html>';

const String consentPage = '<form action="https://consent.youtube.com/s" method="POST">'
    '<input type="hidden" name="v" value="cb.20261115-07-p0.pt+FX+917"></form>';

Map<String, Object?> captionTrack(String code, {bool asr = false, String? name, String extra = '&fmt=srv3'}) => {
      'baseUrl': 'https://www.youtube.com/api/timedtext?v=abcdefghijk&lang=$code$extra${asr ? '&kind=asr' : ''}',
      'name': {
        'runs': [
          {'text': name ?? (asr ? '$code (auto-generated)' : code)},
        ],
      },
      'languageCode': code,
      if (asr) 'kind': 'asr',
      'isTranslatable': true,
    };

Map<String, Object?> playerResponse({List<Map<String, Object?>>? tracks, Map<String, Object?>? status}) => {
      'playabilityStatus': status ?? {'status': 'OK'},
      if (tracks != null)
        'captions': {
          'playerCaptionsTracklistRenderer': {'captionTracks': tracks},
        },
    };

String transcriptXml(List<(double, double, String)> cues) {
  final b = StringBuffer('<?xml version="1.0" encoding="utf-8" ?><transcript>');
  for (final (start, dur, text) in cues) {
    b.write('<text start="$start" dur="$dur">$text</text>');
  }
  b.write('</transcript>');
  return b.toString();
}

/// Um YouTube de mentira: página do vídeo, InnerTube e a faixa em XML.
class FakeYouTube {
  FakeYouTube({
    String? watch,
    Map<String, Object?>? player,
    this.xml = '',
    this.watchStatus = 200,
    this.playerStatus = 200,
  })  : watch = watch ?? watchPage(),
        player = player ?? playerResponse(tracks: [captionTrack('en')]);

  String watch;
  Map<String, Object?> player;
  String xml;
  int watchStatus;
  int playerStatus;

  final List<http.Request> requests = [];

  /// Se a página do vídeo pede o aviso de cookies até receber o cookie CONSENT.
  bool consentUntilCookie = false;

  late final http.Client client = MockClient((req) async {
    requests.add(req);
    switch (req.url.path) {
      case '/watch':
        if (consentUntilCookie && !(req.headers['Cookie'] ?? '').contains('CONSENT=YES+')) {
          return http.Response(consentPage, 200, headers: {'content-type': 'text/html; charset=utf-8'});
        }
        return http.Response.bytes(utf8.encode(watch), watchStatus, headers: {
          'content-type': 'text/html; charset=utf-8',
          'set-cookie': 'YSC=abc123; Domain=.youtube.com; Path=/; Secure, '
              'VISITOR_INFO1_LIVE=xyz; Domain=.youtube.com; Expires=Fri, 14-May-2027 10:00:00 GMT; Path=/',
        });
      case '/youtubei/v1/player':
        return http.Response.bytes(utf8.encode(jsonEncode(player)), playerStatus,
            headers: {'content-type': 'application/json; charset=utf-8'});
      case '/api/timedtext':
        return http.Response.bytes(utf8.encode(xml), 200, headers: {'content-type': 'text/xml; charset=UTF-8'});
    }
    return http.Response('?', 404);
  });
}

/// Espera [condition] ficar verdadeira (sessões rodam em segundo plano).
Future<void> eventually(bool Function() condition, {Duration timeout = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) throw StateError('a condição não ficou verdadeira a tempo');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
