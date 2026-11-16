# Legendas YT (Flutter)

Legendas de vídeos do YouTube com tradução em tempo real (português ⇄ inglês).
Versão Flutter do `app.py` + `tradutor.py` que estão na pasta de cima.

O app abre o vídeo num player do YouTube, baixa a legenda original e mostra,
no tempo do vídeo, a fala original e a tradução — sobre o vídeo e numa lista de
falas que acompanha o vídeo (tocar numa fala leva o vídeo até ela).

## Rodar

```bash
flutter run                      # escolhe o aparelho (iPhone, Android, macOS)
flutter run -d macos
flutter test                     # testes (sem internet)
dart run bin/diagnostico.dart "https://youtu.be/UF8uR6Z6KLc"   # o --diagnostico do app.py
```

Plataformas: Android, iOS e macOS. (Web não dá: o navegador bloqueia os pedidos
ao YouTube. Windows/Linux precisariam de outro pacote de WebView.)

## Do Python para o Dart

| Python | Dart |
| --- | --- |
| `youtube_transcript_api` (página do vídeo → InnerTube como app de Android → XML) | `lib/src/youtube/transcript_api.dart` |
| `extract_video_id`, `video_title` (oEmbed) | `lib/src/youtube/video_id.dart`, `oembed.dart` |
| `pick_transcript`, `make_chunks`, `friendly_error`, `language_name` | `lib/src/core/subtitles.dart` |
| `tradutor.py` (Google em 3 modos, bloqueio por HTTP 429, reserva MyMemory) | `lib/src/translation/translator.dart` |
| classe `Api` (`load`, `_work`, `focus`, `progress`, novas tentativas) | `lib/src/app/session.dart` |
| `History`, `Prefs` (`historico.json`, `preferencias.json`, mesmo formato) | `lib/src/data/history.dart`, `prefs.dart` |
| `ui/index.html` + servidor em `http://localhost` | `lib/src/ui/` (o player é uma página com base `http://localhost/`, sem servidor) |
| `--diagnostico` | `lib/src/core/diagnostics.dart`, menu ⋮ › Diagnóstico, `bin/diagnostico.dart` |

O que muda em relação ao app.py:

- As traduções terminadas também ficam em disco (`cache/`), não só na memória:
  no celular o sistema fecha o app com frequência, e cada tradução gasta a cota do Google.
- Controles de estudo: fala anterior / repetir / próxima, velocidade e tela cheia.
  No computador: espaço, ← →, R, F, + e −.
- A legenda automática do próprio YouTube é desligada ao abrir o vídeo (o app já mostra a dele);
  o botão CC do player liga de novo, se quiser.
- No telefone a interface fica em pé; a tela cheia deita a tela.

Os arquivos ficam na pasta de dados do app: `historico.json`, `preferencias.json`,
`legendas-yt.log` e `cache/`.
