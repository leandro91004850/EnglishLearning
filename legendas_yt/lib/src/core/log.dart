/// Registro do app (o `legendas-yt.log` do app.py).
library;

import 'dart:io';

/// Guarda as últimas linhas em memória (a tela de diagnóstico mostra) e, se
/// [openFile] foi chamado, grava também no arquivo.
abstract final class Log {
  static const int keep = 400;
  static final List<String> lines = [];
  static File? _file;

  /// Repete cada linha em outro lugar (console em modo debug, stderr no CLI).
  static void Function(String line)? echo;

  static String get fileName => _file?.uri.pathSegments.last ?? 'legendas-yt.log';

  static void info(String message) => _add('INFO', message);
  static void warning(String message) => _add('WARNING', message);

  /// Grava em [file]; começa um arquivo novo se o antigo passou de [maxBytes].
  static void openFile(File file, {int maxBytes = 512 * 1024}) {
    try {
      file.parent.createSync(recursive: true);
      if (file.existsSync() && file.lengthSync() > maxBytes) {
        file.renameSync('${file.path}.1');
      }
      _file = file;
    } on FileSystemException {
      _file = null;
    }
  }

  static void _add(String level, String message) {
    final line = '${_stamp(DateTime.now())} $level $message';
    lines.add(line);
    if (lines.length > keep) lines.removeRange(0, lines.length - keep);
    echo?.call(line);
    final file = _file;
    if (file == null) return;
    try {
      file.writeAsStringSync('$line\n', mode: FileMode.append);
    } on FileSystemException {
      _file = null; // sem espaço ou sem permissão: segue só em memória
    }
  }

  static String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    final ms = t.millisecond.toString().padLeft(3, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)},$ms';
  }
}
