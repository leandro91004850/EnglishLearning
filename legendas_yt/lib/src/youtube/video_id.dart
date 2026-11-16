final RegExp _idOnly = RegExp(r'^[\w-]{11}$');
final RegExp _idInUrl = RegExp(r'(?:[?&]v=|youtu\.be/|/shorts/|/embed/|/live/)([\w-]{11})');

/// `extract_video_id()` do app.py: aceita o ID puro ou links como
/// `youtube.com/watch?v=`, `youtu.be/`, `/shorts/`, `/embed/` e `/live/`.
String? extractVideoId(String? text) {
  final t = (text ?? '').trim();
  if (_idOnly.hasMatch(t)) return t;
  return _idInUrl.firstMatch(t)?.group(1);
}

bool isVideoId(String? text) => text != null && _idOnly.hasMatch(text);

final RegExp _startParam = RegExp(r'[?&#](?:t|start)=(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s?)?(?:&|$)');

/// O tempo inicial que o link pede (`?t=90`, `&t=1m30s`, `?start=90`), ou null.
double? startTimeFromUrl(String? url) {
  final m = _startParam.firstMatch(url ?? '');
  if (m == null || (m[1] == null && m[2] == null && m[3] == null)) return null;
  int part(int i) => int.tryParse(m[i] ?? '') ?? 0;
  return (part(1) * 3600 + part(2) * 60 + part(3)).toDouble();
}

String watchUrlFor(String videoId) => 'https://www.youtube.com/watch?v=$videoId';

String thumbnailFor(String videoId) => 'https://i.ytimg.com/vi/$videoId/mqdefault.jpg';
