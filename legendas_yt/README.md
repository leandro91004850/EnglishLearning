# Legendas YT (Flutter)

Inglês com os vídeos que você assiste: legendas de vídeos do YouTube com tradução em tempo real
(português ⇄ inglês) e um quiz para formar frases com as falas desses vídeos.

O app abre num menu com três caminhos:

- **Vídeos**: o vídeo num player do YouTube com a fala original e a tradução, no tempo do vídeo —
  sobre o vídeo e numa lista de falas que acompanha o vídeo (tocar numa fala leva o vídeo até ela).
- **Formar frases**: "Traduza esta frase", como no Duolingo. Uma frase em inglês das suas legendas e a
  tradução para montar com as fichas, das palavras que mais aparecem nas legendas para as que menos.
- **Palavras mais usadas**: o ranking das palavras em inglês das suas legendas; tocar numa abre o quiz
  na frase dela.

No menu ficam também os números do banco (vídeos, falas e palavras diferentes), a próxima palavra do
quiz e os botões Servidor, Diagnóstico e Sobre.

**O app é só um consumidor da API do Legendas YT** (o servidor em Python, projeto `api_english`):
a lista de vídeos, as preferências, as legendas com a tradução, as frases do quiz e o diagnóstico vêm
de lá. O app não fala com o banco de dados, com o Google Tradutor nem com as legendas do YouTube; ele
só toca o vídeo no player do YouTube.

## Rodar

1. Ligue a API (veja o README do `api_english`): `python -m legendas_api`.
2. Rode o app e toque em **Servidor** (no rodapé do menu; na tela dos vídeos, ⋮ › Servidor). Preencha
   o endereço da API: no simulador do iPhone e no Mac, `http://localhost:8000`; no celular, o endereço
   (IP) do computador onde a API roda, por exemplo `http://192.168.0.10:8000`. Se a API tiver chave
   (`API_TOKEN` no `.env` dela), preencha a chave também.

```bash
flutter run                      # escolhe o aparelho (iPhone, Android, macOS)
flutter run -d macos
flutter test                     # testes (sem internet e sem a API: uma API de mentira)
```

Plataformas: Android, iOS e macOS. (Web não dá: o player precisa de WebView. Windows/Linux
precisariam de outro pacote de WebView.)

## Como funciona

| No app | Na API |
| --- | --- |
| `lib/src/api/api_client.dart`: as chamadas à API e as mensagens de erro | `legendas_api/main.py`: as rotas |
| `lib/src/ui/menu_page.dart`: o menu, com os números do banco e a próxima palavra do quiz | `GET /palavras` e `GET /quiz` |
| `lib/src/app/session.dart`: abre o vídeo na API e pergunta pelo andamento da legenda, avisa onde o vídeo está | `legendas_api/servico.py`: busca a legenda (banco ou YouTube) e traduz em lotes, começando pelo trecho onde o vídeo está |
| `lib/src/data/history.dart`: a lista de vídeos na tela; manda a nova ordem e onde cada vídeo parou | a lista no banco, com todos os vídeos |
| `lib/src/data/prefs.dart`: tamanho da legenda, o que mostrar e onde o quiz parou | tabela `preferencias` |
| `lib/src/quiz/quiz_session.dart`: as lições do quiz, conferir a resposta, guardar onde parou | `GET /quiz`: `legendas_api/quiz.py` analisa as falas do banco e monta as frases com as fichas |
| `lib/src/ui/quiz_page.dart`: a tela "Traduza esta frase"; `lib/src/quiz/speaker.dart`: a voz | — |
| `lib/src/ui/words_page.dart`: o ranking das palavras | `GET /palavras` |
| Diagnóstico | `GET /diagnostico`: testa o banco, os tradutores e as legendas do vídeo |
| `lib/src/ui/`: o player do YouTube (uma página com base `http://localhost/`, sem servidor) e a interface | — |

### Vídeos

- O botão Vídeos do menu volta ao último vídeo, de onde ele parou; a seta no alto volta ao menu.
- Recentes não tem limite de vídeos: é uma lista só, com todos os vídeos guardados no banco (a aba
  mostra quantos são), e por isso não tem o × (um vídeo tirado dela voltaria). Tocar e segurar um
  vídeo e arrastar para cima ou para baixo muda a ordem. Quando um vídeo termina, o app segue para o
  de baixo — só se o vídeo chegou mesmo ao fim (o player às vezes avisa "terminou" antes da hora).
- Controles de estudo: fala anterior / repetir / próxima, velocidade e tela cheia.
  No computador: espaço, ← →, R, F, + e −.
- A legenda automática do próprio YouTube é desligada ao abrir o vídeo (o app já mostra a dele);
  o botão CC do player liga de novo, se quiser.
- No telefone a interface fica em pé; a tela cheia deita a tela.
- Com a API fora do ar (ou o banco dela com problema), aparece um aviso vermelho no menu e, na tela dos
  vídeos, abaixo do status, com um ponto vermelho no ⋮; tocar no aviso abre Servidor. O vídeo toca, mas
  sem legenda.

### Formar frases

- A API passa por todas as falas guardadas no banco (com inglês e português) e conta quantas vezes
  cada palavra em inglês aparece. O quiz vai da palavra que mais se repete para a que menos: para cada
  palavra, uma frase curta com ela — a que mais se repete nas legendas (refrões, bordões). A palavra
  vem destacada na frase, com quantas vezes ela aparece nas suas legendas.
- A frase é lida em voz alta quando aparece (a voz em inglês do aparelho); o alto-falante lê de novo.
- Monte a tradução tocando nas fichas, na ordem; tocar numa ficha da resposta devolve ela. Algumas
  fichas sobram (palavras de outras frases). **VERIFICAR** confere (maiúsculas não contam) e, se errou,
  mostra a solução certa.
- Lições de 10 frases; a frase errada volta uma vez no fim da lição. **Ver no vídeo** abre o vídeo da
  frase, no ponto dela.
- Onde o quiz parou fica na API (preferência `quizPos`): a próxima lição começa dali, em qualquer
  aparelho. Praticar uma palavra escolhida no ranking não muda onde o quiz parou. Feitas todas as
  frases, dá para recomeçar do início; vídeos novos trazem frases novas.

### Palavras mais usadas

As 300 palavras em inglês que mais aparecem nas suas legendas, com quantas vezes e em quantas falas. O
botão verde abre o quiz na frase da palavra.

No aparelho ficam só o `servidor.json` (endereço e chave da API) e o `legendas-yt.log`, na pasta de
dados do app.

## Servidor (API)

- **No celular**, "localhost" é o próprio celular: use o endereço (IP) do computador onde a API roda,
  e deixe a API escutar na rede (`API_HOST=0.0.0.0`, o padrão). No iPhone, o iOS pede permissão de
  "Rede Local" na primeira conexão.
- O app aceita `http://` (rede de casa) e `https://`. Fora de casa, ponha a API atrás de HTTPS e use
  uma chave (`API_TOKEN`).
- O banco de dados (PostgreSQL) agora é configurado só na API, no `.env` dela: o mesmo banco do app
  Python legendas-yt.

## Ícone

Uma tela de vídeo em forma de balão de fala, com a legenda dupla do app: a fala original em branco e a
tradução em amarelo. O desenho é feito em código, no `tool/icone/desenhar_icone.swift`; depois de mudar
o desenho, rode num Mac:

```bash
sh tool/icone/gerar.sh
```

O script grava todos os tamanhos do iOS, do macOS e do Android (com o ícone adaptativo do Android 8+) e o
`assets/icone.png`, que aparece em ⋮ › Sobre.
