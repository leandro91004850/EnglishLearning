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
- Recentes não tem limite de vídeos (o app.py guardava só os últimos 30): com o banco de dados, é
  uma lista só, com todos os vídeos guardados lá, e a aba mostra quantos são. Por isso, com o banco,
  a lista não tem o × (um vídeo tirado dela voltaria); sem banco, o × tira o vídeo da lista.
  Tocar e segurar um vídeo e arrastar para cima ou para baixo muda a ordem
  (no lugar das setas do app.py). Quando um vídeo termina, o app segue para o de baixo —
  só se o vídeo chegou mesmo ao fim (o player às vezes avisa "terminou" antes da hora).
- Controles de estudo: fala anterior / repetir / próxima, velocidade e tela cheia.
  No computador: espaço, ← →, R, F, + e −.
- A legenda automática do próprio YouTube é desligada ao abrir o vídeo (o app já mostra a dele);
  o botão CC do player liga de novo, se quiser.
- No telefone a interface fica em pé; a tela cheia deita a tela.

Os arquivos ficam na pasta de dados do app: `historico.json`, `preferencias.json`,
`legendas-yt.log`, `cache/` e o `.env` do banco de dados.

## Banco de dados (PostgreSQL)

A mesma lógica do `banco.py` do projeto [legendas-yt](https://github.com/leandro91004850/legendas-yt),
com **o mesmo esquema**: o app Python do computador e este app podem usar o mesmo banco. Ficam no
PostgreSQL a lista de Recentes (com onde cada vídeo parou), as preferências, as legendas de cada vídeo
com a tradução de cada fala e as palavras de cada fala (tabelas `videos`, `recentes`, `preferencias`,
`legendas`, `legendas_escolhidas`, `frases`, `palavras`, `frases_palavras` e a view `frases_en_pt`).
Um vídeo que já foi aberto volta do banco na hora, sem baixar a legenda nem traduzir de novo; se a
tradução tinha parado no meio, o app traduz só o que falta.

A lista de Recentes tem todos os vídeos do banco, sem limite. Sempre que o app lê a lista, os vídeos do
banco que não estão nela entram no fim, os mais novos primeiro: os que uma versão antiga, ainda com o
limite de 30, cortou, e os tirados com × no app Python (o app Python grava a lista do banco, então ele
também passa a mostrar todos). Enquanto um vídeo toca, só a posição dele vai para o banco, não a lista
inteira.

1. No app, abra **⋮ › Banco de dados** e preencha servidor, porta, banco, usuário e senha.
   **Testar** conecta sem gravar nada; **Salvar** grava e o app passa a usar esse banco na hora.
   Servidor na nuvem: escolha **Exigir** em "Conexão segura (SSL)".
2. Os dados de acesso ficam num arquivo `.env` na pasta privada do app, no aparelho (o modelo, sem
   senha, é o `.env.example`). Se o banco `legendas_yt` não existir, o app tenta criá-lo; as tabelas
   ele cria sozinho.
3. **No celular**, "localhost" é o próprio celular: use o endereço (IP) do computador onde está o
   PostgreSQL, e deixe o servidor aceitar conexões da rede (`listen_addresses` no
   `postgresql.conf` e uma linha para a rede no `pg_hba.conf`). No iPhone, o iOS pede permissão de
   "Rede Local" na primeira conexão.

Sem banco (não configurado ou fora do ar) o app funciona e guarda tudo no aparelho; com problema, aparece
um aviso vermelho abaixo do status e um ponto vermelho no ⋮. Quando o banco volta, o que foi feito no
aparelho vai para lá: os vídeos mexidos ficam por cima da lista do banco. As gravações vão numa fila, sem
travar a tela; o diagnóstico (⋮ › Diagnóstico, ou `dart run bin/diagnostico.dart` com um `.env` nesta
pasta) testa o banco primeiro e conta o que já está guardado.

## Ícone

Uma tela de vídeo em forma de balão de fala, com a legenda dupla do app: a fala original em branco e a
tradução em amarelo. O desenho é feito em código, no `tool/icone/desenhar_icone.swift`; depois de mudar
o desenho, rode num Mac:

```bash
sh tool/icone/gerar.sh
```

O script grava todos os tamanhos do iOS, do macOS e do Android (com o ícone adaptativo do Android 8+) e o
`assets/icone.png`, que aparece em ⋮ › Sobre.
