import 'dart:convert';
import 'dart:io';

import '../core/log.dart';

/// Conteúdo do arquivo, ou [fallback] se ele não existir, estiver estragado ou for de outro tipo.
T readJson<T>(File file, T fallback) {
  try {
    if (!file.existsSync()) return fallback;
    final data = jsonDecode(file.readAsStringSync());
    return data is T ? data : fallback;
  } on FileSystemException catch (e) {
    Log.warning('Arquivo ilegível (${file.path}): $e');
  } on FormatException catch (e) {
    Log.warning('Arquivo ilegível (${file.path}): $e');
  }
  return fallback;
}

/// Grava sem deixar arquivo pela metade (escreve num temporário e troca).
bool writeJson(File file, Object data) {
  try {
    file.parent.createSync(recursive: true);
    final tmp = File('${file.path}.tmp');
    tmp.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(data), flush: true);
    tmp.renameSync(file.path);
    return true;
  } on FileSystemException catch (e) {
    Log.warning('Não consegui gravar ${file.path}: $e');
    return false;
  }
}
