/// Funções de texto usadas no app todo (portadas de app.py e tradutor.py).
library;

final RegExp _spaces = RegExp(r'\s+');
final RegExp _invisible = RegExp('[​﻿]');

/// `clean()` do app.py: troca qualquer sequência de espaços e quebras de linha
/// por um espaço só e tira os das pontas.
String clean(String? text) => (text ?? '').replaceAll(_spaces, ' ').trim();

/// `_one_line()` do tradutor.py: como [clean], mas antes tira o espaço de
/// largura zero e o BOM que o Google às vezes põe no texto.
String oneLine(String? text) => clean((text ?? '').replaceAll(_invisible, ''));

final RegExp _entity = RegExp(
  r'&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[A-Za-z][A-Za-z0-9]{1,31});',
);

const Map<String, String> _named = {
  'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' ',
  'hellip': '…', 'mdash': '—', 'ndash': '–', 'lsquo': '‘', 'rsquo': '’',
  'sbquo': '‚', 'ldquo': '“', 'rdquo': '”', 'bdquo': '„', 'laquo': '«',
  'raquo': '»', 'bull': '•', 'middot': '·', 'copy': '©', 'reg': '®',
  'trade': '™', 'deg': '°', 'euro': '€', 'pound': '£', 'cent': '¢',
  'yen': '¥', 'sect': '§', 'para': '¶', 'times': '×', 'divide': '÷',
  'iexcl': '¡', 'iquest': '¿', 'ordf': 'ª', 'ordm': 'º', 'shy': '­',
  'Agrave': 'À', 'Aacute': 'Á', 'Acirc': 'Â', 'Atilde': 'Ã', 'Auml': 'Ä',
  'Ccedil': 'Ç', 'Egrave': 'È', 'Eacute': 'É', 'Ecirc': 'Ê', 'Euml': 'Ë',
  'Igrave': 'Ì', 'Iacute': 'Í', 'Icirc': 'Î', 'Iuml': 'Ï', 'Ntilde': 'Ñ',
  'Ograve': 'Ò', 'Oacute': 'Ó', 'Ocirc': 'Ô', 'Otilde': 'Õ', 'Ouml': 'Ö',
  'Ugrave': 'Ù', 'Uacute': 'Ú', 'Ucirc': 'Û', 'Uuml': 'Ü',
  'agrave': 'à', 'aacute': 'á', 'acirc': 'â', 'atilde': 'ã', 'auml': 'ä',
  'ccedil': 'ç', 'egrave': 'è', 'eacute': 'é', 'ecirc': 'ê', 'euml': 'ë',
  'igrave': 'ì', 'iacute': 'í', 'icirc': 'î', 'iuml': 'ï', 'ntilde': 'ñ',
  'ograve': 'ò', 'oacute': 'ó', 'ocirc': 'ô', 'otilde': 'õ', 'ouml': 'ö',
  'ugrave': 'ù', 'uacute': 'ú', 'ucirc': 'û', 'uuml': 'ü', 'szlig': 'ß',
};

/// O `html.unescape()` do Python, para o que aparece em legendas e traduções:
/// entidades numéricas (`&#39;`, `&#x27;`) e as nomeadas mais comuns.
String unescapeHtml(String text) {
  if (!text.contains('&')) return text;
  return text.replaceAllMapped(_entity, (m) {
    final entity = m[1]!;
    if (!entity.startsWith('#')) return _named[entity] ?? m[0]!;
    final hex = entity.length > 1 && (entity[1] == 'x' || entity[1] == 'X');
    final code = int.tryParse(entity.substring(hex ? 2 : 1), radix: hex ? 16 : 10);
    if (code == null || code == 0 || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) {
      return '�';
    }
    return String.fromCharCode(code);
  });
}

String _two(int n) => n.toString().padLeft(2, '0');

/// 75 -> "1:15"; 3725 -> "1:02:05".
String formatTime(double seconds) {
  final s = seconds.isFinite && seconds > 0 ? seconds.floor() : 0;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, rest = s % 60;
  return h > 0 ? '$h:${_two(m)}:${_two(rest)}' : '$m:${_two(rest)}';
}

/// "15:30" (hora local).
String hourMinute(DateTime t) {
  final local = t.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}';
}

/// 5000 -> "5.000", como o `f"{n:,}".replace(",", ".")` do app.py.
String thousands(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Data curta para a tela: "hoje, 13:40", "ontem, 09:05" ou "20/11/2026" (na hora local).
String dayAndTime(DateTime when, {DateTime? now}) {
  final local = when.toLocal();
  final today = now ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(local.hour)}:${two(local.minute)}';
  final day = DateTime(local.year, local.month, local.day);
  final days = DateTime(today.year, today.month, today.day).difference(day).inDays;
  if (days == 0) return 'hoje, $time';
  if (days == 1) return 'ontem, $time';
  return '${two(local.day)}/${two(local.month)}/${local.year}';
}

/// Há quanto tempo, em dias: "hoje", "ontem" ou "há 3 dias" (na hora local).
String daysAgo(DateTime when, {DateTime? now}) {
  final local = when.toLocal();
  final today = now ?? DateTime.now();
  final days = DateTime(today.year, today.month, today.day).difference(DateTime(local.year, local.month, local.day)).inDays;
  if (days <= 0) return 'hoje';
  if (days == 1) return 'ontem';
  return 'há $days dias';
}
