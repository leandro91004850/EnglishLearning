import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/text.dart';
import 'video_id.dart';

/// `video_title()` do app.py: título e canal do vídeo pelo oEmbed do YouTube;
/// `('', '')` se não der.
Future<(String title, String author)> videoTitle(http.Client client, String videoId) async {
  try {
    final uri = Uri.https('www.youtube.com', '/oembed', {
      'url': watchUrlFor(videoId),
      'format': 'json',
    });
    final r = await client.get(uri).timeout(const Duration(seconds: 16));
    if (r.statusCode < 400) {
      final data = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
      if (data is Map) {
        return (clean(data['title']?.toString()), clean(data['author_name']?.toString()));
      }
    }
  } on Exception {
    // sem título: a lista mostra o ID
  }
  return ('', '');
}
