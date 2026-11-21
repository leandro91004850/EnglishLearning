// Diagnóstico sem abrir o app, como o `python app.py --diagnostico [link]`:
//
//   dart run bin/diagnostico.dart                     # testa o banco (.env daqui) e os tradutores
//   dart run bin/diagnostico.dart "https://youtu.be/…" # e as legendas do vídeo
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:legendas_yt/src/core/diagnostics.dart';
import 'package:legendas_yt/src/core/log.dart';
import 'package:legendas_yt/src/data/banco.dart';
import 'package:legendas_yt/src/translation/translator.dart';
import 'package:legendas_yt/src/youtube/transcript_api.dart';

Future<void> main(List<String> args) async {
  Log.echo = stderr.writeln;
  final client = http.Client();
  // o .env desta pasta (o modelo é o .env.example), como o app.py
  final env = File('.env');
  final banco = env.existsSync() ? Banco.fromEnv(env) : null;
  final diagnostics = Diagnostics(
    translation: TranslationService(client: client),
    transcripts: TranscriptApi(client: client),
    banco: banco,
  );
  await for (final line in diagnostics.run(url: args.isEmpty ? null : args.first)) {
    stdout.writeln(line);
  }
  client.close();
  await banco?.close();
  exit(diagnostics.translatorsOk > 0 ? 0 : 1);
}
