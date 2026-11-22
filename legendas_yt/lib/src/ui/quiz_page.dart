import 'dart:async';
import 'dart:math' show Random;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../app/services.dart';
import '../core/text.dart';
import '../quiz/pronunciation.dart';
import '../quiz/quiz_session.dart';
import '../quiz/speaker.dart';
import '../quiz/voice_input.dart';
import '../youtube/video_id.dart';
import 'home_page.dart';
import 'theme.dart';

const Color kQuizGreen = Color(0xFF93D333);
const Color kQuizGreenDark = Color(0xFF14240A);
const Color kQuizRed = Color(0xFFFF5A5A);
const Color kQuizPurple = Color(0xFFCE82FF);
const Color kQuizBlue = Color(0xFF49C0F8);
const Color kQuizBlueDark = Color(0xFF1C8FC4);
const Color kQuizBlueDeep = Color(0xFF0F2A38);
const Color kQuizOrange = Color(0xFFFF9600);
const Color kTileBorder = Color(0xFF3A3A42);

final RegExp _notWord = RegExp(r"[^\p{L}'’\-]", unicode: true);

/// As lições, como no Duolingo: exercícios sorteados com as frases das legendas do banco, das
/// palavras que mais se repetem para as que menos — "Traduza esta frase" (montar a tradução com
/// as fichas) e "Repita esta frase" (falar; o reconhecimento de voz do aparelho confere a
/// pronúncia). [startAt]: praticar a partir de uma palavra escolhida (sem mudar onde o quiz parou).
class QuizPage extends StatefulWidget {
  const QuizPage({
    super.key,
    required this.services,
    this.startAt,
    this.speaker,
    this.voice,
    this.speakShare = QuizSession.defaultSpeakShare,
    this.review = false,
    this.matching = true,
    this.matchAt,
    this.random,
  });

  final AppServices services;
  final int? startAt;

  /// A voz que lê a frase (os testes passam uma muda).
  final Speaker? speaker;

  /// O microfone (sem ele, o do aparelho; os testes passam um de mentira).
  final VoiceInput? voice;

  /// A parte das frases que vira exercício de falar.
  final double speakShare;

  /// A revisão: as palavras erradas ainda não revisadas primeiro, depois as com mais erros e há mais
  /// tempo sem revisar (onde o quiz parou não muda).
  final bool review;

  /// Cada lição ganha um "Combine os pares" com as palavras dela.
  final bool matching;

  /// Os testes fixam onde o "Combine os pares" entra e o sorteio.
  final int? matchAt;
  final Random? random;

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  late final QuizSession quiz = QuizSession(
    api: widget.services.api,
    prefs: widget.services.prefs,
    voice: widget.voice ?? DeviceVoiceInput.instance,
    speakShare: widget.speakShare,
    review: widget.review,
    matching: widget.matching,
    matchAt: widget.matchAt,
    random: widget.random,
  );
  late final Speaker speaker = widget.speaker ?? DeviceSpeaker();
  int? _spoken; // a frase (QuizSession.turn) já lida em voz alta

  @override
  void initState() {
    super.initState();
    quiz.addListener(_readAloud);
    unawaited(quiz.start(at: widget.startAt));
  }

  @override
  void dispose() {
    quiz.removeListener(_readAloud);
    quiz.dispose();
    unawaited(speaker.stop());
    super.dispose();
  }

  /// Cada frase nova é lida uma vez, como no Duolingo.
  void _readAloud() {
    final item = quiz.current;
    if (item == null || quiz.loading || quiz.correct != null || quiz.turn == _spoken) return;
    _spoken = quiz.turn;
    unawaited(speaker.say(item.phrase));
  }

  /// Arquivar a frase (ela não aparece mais nas lições), depois de confirmar.
  Future<void> _archive(QuizItem item) async {
    quiz.cancelListening();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.archive_outlined),
        title: const Text('Arquivar esta frase?'),
        content: Text(
          '“${item.phrase}”\n\nEla não vai mais aparecer nas lições. Para trazê-la de volta, use '
          '"frases arquivadas" no cartão Lições do menu.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Arquivar')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    unawaited(speaker.stop());
    final messenger = ScaffoldMessenger.of(context);
    if (await quiz.archiveCurrent()) {
      messenger.showSnackBar(const SnackBar(content: Text('Frase arquivada: ela não aparece mais nas lições.')));
    }
  }

  /// Ouvir a frase de novo (o microfone desliga, para não ouvir a própria voz do aparelho).
  Future<void> _say(String text) async {
    quiz.cancelListening();
    await speaker.say(text);
  }

  /// O botão do microfone: começa a ouvir, ou termina e confere.
  Future<void> _mic() async {
    if (quiz.listening) return quiz.stopListening();
    await speaker.stop();
    await quiz.listen();
  }

  void _openVideo(QuizItem item) {
    quiz.cancelListening();
    unawaited(speaker.stop());
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => HomePage(services: widget.services, startVideo: item.videoId, startAt: item.start),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: quiz,
          builder: (context, _) {
            final Widget body;
            if (quiz.loading) {
              body = _Message(
                icon: null,
                title: quiz.review ? 'Separando as palavras para revisar…' : 'Analisando as frases das suas legendas…',
                text: quiz.review
                    ? 'Primeiro as que você errou e ainda não revisou.'
                    : 'As palavras que mais se repetem vêm primeiro.',
              );
            } else if (quiz.error.isNotEmpty) {
              body = _Message(
                icon: Icons.cloud_off_rounded,
                title: 'Não deu para carregar as frases',
                text: quiz.error,
                button: 'TENTAR DE NOVO',
                onButton: () => quiz.start(at: widget.startAt),
              );
            } else if (quiz.nothingToReview) {
              body = _Message(
                icon: Icons.verified_rounded,
                title: 'Nada para revisar agora',
                text: 'Você revisou todas as palavras que errou. As que você já acertou de novo voltam para a '
                    'revisão um dia depois do último teste.',
                button: 'VOLTAR',
                onButton: () => Navigator.of(context).maybePop(),
              );
            } else if (quiz.completedAll) {
              body = _Message(
                icon: Icons.celebration_rounded,
                title: 'Você fez todas as ${thousands(quiz.total)} frases!',
                text: 'Todas as frases das suas legendas, da palavra que mais se repete à que menos. '
                    'Abra vídeos novos para ganhar frases novas, ou recomece do início.',
                button: 'RECOMEÇAR',
                onButton: () {
                  widget.services.prefs.quizPos = 0;
                  quiz.start();
                },
              );
            } else if (quiz.finished) {
              body = _Message(
                icon: Icons.emoji_events_rounded,
                iconColor: const Color(0xFFFFC800),
                title: quiz.review ? 'Revisão completa!' : 'Lição completa!',
                text: '${quiz.right} acertos em ${quiz.answered} respostas.',
                button: 'CONTINUAR',
                onButton: () => quiz.start(at: widget.startAt == null ? null : widget.startAt! + quiz.lessonSize),
                secondary: 'Voltar ao menu',
                onSecondary: () => Navigator.of(context).maybePop(),
              );
            } else {
              body = quiz.exercise == Exercise.match
                  ? _MatchQuestion(quiz: quiz, onSpeak: _say)
                  : _Question(quiz: quiz, onSpeak: _say, onMic: _mic, onOpenVideo: _openVideo, onArchive: _archive);
            }
            return Column(
              children: [
                _Header(progress: quiz.progress, right: quiz.right, onClose: () => Navigator.of(context).maybePop()),
                Expanded(child: body),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.progress, required this.right, required this.onClose});

  final double progress;
  final int right;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 4),
      child: Row(
        children: [
          IconButton(tooltip: 'Fechar', onPressed: onClose, icon: const Icon(Icons.close, size: 28)),
          const SizedBox(width: 4),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: progress),
                duration: const Duration(milliseconds: 350),
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 16,
                  color: kQuizGreen,
                  backgroundColor: kPanelHigh,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.local_fire_department_rounded, color: Color(0xFFFF9600)),
          const SizedBox(width: 2),
          Text(
            '$right',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFFFF9600),
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _Question extends StatelessWidget {
  const _Question({
    required this.quiz,
    required this.onSpeak,
    required this.onMic,
    required this.onOpenVideo,
    required this.onArchive,
  });

  final QuizSession quiz;
  final Future<void> Function(String) onSpeak;
  final VoidCallback onMic;
  final ValueChanged<QuizItem> onOpenVideo;
  final ValueChanged<QuizItem> onArchive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = quiz.current!;
    final checked = quiz.correct != null;
    final speaking = quiz.exercise == Exercise.speak;
    final check = quiz.speech;
    final review = item.review;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      review == null ? Icons.auto_awesome : Icons.replay_rounded,
                      color: review == null ? kQuizPurple : kQuizOrange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        review == null
                            ? 'PALAVRA FREQUENTE Nº ${thousands(item.position)}'
                            : review.pending
                                ? 'REVISÃO · AINDA NÃO REVISADA'
                                : 'REVISÃO',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: review == null ? kQuizPurple : kQuizOrange,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    if (quiz.archiving)
                      const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      IconButton(
                        tooltip: 'Arquivar esta frase',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => onArchive(item),
                        icon: Icon(Icons.archive_outlined, color: theme.colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  speaking ? 'Repita esta frase:' : 'Traduza esta frase:',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 20),
                _Speech(item: item, onSpeak: () => onSpeak(item.phrase), marks: speaking ? check?.words : null),
                const SizedBox(height: 10),
                Text(
                  review == null
                      ? '"${item.word}" aparece ${thousands(item.times)} vezes nas suas legendas'
                      : '"${item.word}": você errou ${review.wrong} de ${review.wrong + review.right} '
                          '${review.wrong + review.right == 1 ? 'vez' : 'vezes'}'
                          '${review.lastTest == null ? '' : ' · último teste ${daysAgo(review.lastTest!)}'}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                if (quiz.note.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _Note(text: quiz.note),
                ],
                if (speaking) ...[
                  const SizedBox(height: 24),
                  _Hearing(listening: quiz.listening, text: quiz.hearing),
                ] else ...[
                  const SizedBox(height: 22),
                  _AnswerArea(
                    tiles: [for (final i in quiz.picked) (i, item.tiles[i])],
                    onTap: checked ? null : quiz.unpick,
                  ),
                  const SizedBox(height: 30),
                  _Bank(tiles: item.tiles, used: quiz.picked.toSet(), onTap: checked ? null : quiz.pick),
                ],
              ],
            ),
          ),
        ),
        if (checked)
          _Feedback(
            correct: quiz.correct!,
            item: item,
            title: quiz.correct!
                ? (speaking && check?.percent == 100 ? 'Pronúncia perfeita!' : 'Muito bem!')
                : (speaking ? 'Ouvi outra coisa:' : 'Solução correta:'),
            text: !speaking
                ? item.translation
                : quiz.correct!
                    ? 'Significa: ${item.translation}'
                    : '“${quiz.hearing}”',
            details: [
              if (speaking) 'Pronúncia: ${check?.percent ?? 0}%',
              if (!quiz.correct!) 'Esta frase volta no fim da lição.',
            ],
            onContinue: quiz.next,
            onOpenVideo: () => onOpenVideo(item),
          )
        else if (speaking)
          _SpeakControls(listening: quiz.listening, level: quiz.level, onMic: onMic, onCantSpeak: quiz.cantSpeakNow)
        else
          _BottomButton(
            label: 'VERIFICAR',
            color: kQuizGreen,
            onPressed: quiz.canCheck ? quiz.check : null,
          ),
      ],
    );
  }
}

/// "Combine os pares": as traduções à esquerda e as palavras em inglês à direita, embaralhadas.
/// Toque numa de cada lado: o par certo fica apagado; o errado pisca em vermelho.
class _MatchQuestion extends StatelessWidget {
  const _MatchQuestion({required this.quiz, required this.onSpeak});

  final QuizSession quiz;
  final Future<void> Function(String) onSpeak;

  /// "i" e "i'm" com maiúscula, como se escreve.
  static String _english(String word) => word == 'i' || word.startsWith("i'") ? 'I${word.substring(1)}' : word;

  _PairState _state(int pair, {required bool left}) {
    if (quiz.matched.contains(pair)) return _PairState.matched;
    final wrong = quiz.wrongPair;
    if (wrong != null && (left ? wrong.$1 : wrong.$2) == pair) return _PairState.wrong;
    return (left ? quiz.pickedLeft : quiz.pickedRight) == pair ? _PairState.picked : _PairState.idle;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pairs = quiz.pairs;
    final done = quiz.correct != null;
    final missed = [for (final i in quiz.missed) _english(pairs[i].word)];
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.join_inner_rounded, color: kQuizBlue, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'PALAVRAS DESTA LIÇÃO',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: kQuizBlue,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Combine os pares:', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 28),
                for (var row = 0; row < pairs.length; row++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: _PairTile(
                            text: pairs[quiz.leftOrder[row]].translation,
                            state: _state(quiz.leftOrder[row], left: true),
                            onTap: done ? null : () => quiz.pickLeft(quiz.leftOrder[row]),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _PairTile(
                            text: _english(pairs[quiz.rightOrder[row]].word),
                            state: _state(quiz.rightOrder[row], left: false),
                            onTap: done
                                ? null
                                : () {
                                    final pair = quiz.rightOrder[row];
                                    unawaited(onSpeak(pairs[pair].word));
                                    quiz.pickRight(pair);
                                  },
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (done)
          _Feedback(
            correct: true,
            title: missed.isEmpty ? 'Muito bem!' : 'Pares combinados!',
            text: 'Você combinou os ${pairs.length} pares.',
            details: [
              if (missed.isNotEmpty)
                '${missed.length == 1 ? 'Errou o par de' : 'Errou os pares de'} ${missed.join(', ')}: '
                    '${missed.length == 1 ? 'ela conta' : 'elas contam'} como erro nos seus resultados.',
            ],
            onContinue: quiz.next,
            onOpenVideo: () {},
          ),
      ],
    );
  }
}

enum _PairState { idle, picked, matched, wrong }

class _PairTile extends StatelessWidget {
  const _PairTile({required this.text, required this.state, required this.onTap});

  final String text;
  final _PairState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (state) {
      _PairState.picked => kQuizBlue,
      _PairState.wrong => kQuizRed,
      _PairState.matched => kTileBorder.withValues(alpha: 0.6),
      _PairState.idle => kTileBorder,
    };
    final side = BorderSide(color: color, width: 2);
    return GestureDetector(
      onTap: state == _PairState.matched ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: switch (state) {
            _PairState.picked => kQuizBlue.withValues(alpha: 0.14),
            _PairState.wrong => kQuizRed.withValues(alpha: 0.14),
            _PairState.matched => Colors.transparent,
            _PairState.idle => kPanelHigh,
          },
          borderRadius: BorderRadius.circular(14),
          border: Border(
            top: side,
            left: side,
            right: side,
            bottom: BorderSide(color: color, width: state == _PairState.matched ? 2 : 4),
          ),
        ),
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 18,
              color: switch (state) {
                _PairState.picked => kQuizBlue,
                _PairState.wrong => kQuizRed,
                _PairState.matched => theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                _PairState.idle => null,
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Um aviso com a frase: nada ouvido, "fale de novo", sem microfone.
class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, color: kQuizOrange, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: kQuizOrange)),
        ),
      ],
    );
  }
}

/// O que o aparelho está ouvindo (e, depois, o que ouviu).
class _Hearing extends StatelessWidget {
  const _Hearing({required this.listening, required this.text});

  final bool listening;
  final String text;

  @override
  Widget build(BuildContext context) {
    if (!listening && text.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kTileBorder, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            listening ? 'OUVINDO…' : 'OUVI',
            style: theme.textTheme.labelMedium?.copyWith(
              color: kQuizBlue,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(text.isEmpty ? '…' : '“$text”', style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}

/// O microfone grande e o "não posso falar agora", como no Duolingo.
class _SpeakControls extends StatelessWidget {
  const _SpeakControls({required this.listening, required this.level, required this.onMic, required this.onCantSpeak});

  final bool listening;
  final ValueListenable<double> level;
  final VoidCallback onMic;
  final VoidCallback onCantSpeak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MicButton(listening: listening, level: level, onTap: onMic),
          const SizedBox(height: 10),
          Text(
            listening ? 'Ouvindo… toque para terminar' : 'Toque no microfone e fale a frase',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: onCantSpeak,
            style: TextButton.styleFrom(foregroundColor: muted),
            child: const Text(
              'NÃO POSSO FALAR AGORA',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1),
            ),
          ),
        ],
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.listening, required this.level, required this.onTap});

  final bool listening;
  final ValueListenable<double> level;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: listening ? 'Parar de ouvir' : 'Falar',
      child: Semantics(
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: double.infinity,
              height: 80,
              decoration: BoxDecoration(
                color: listening ? kQuizBlueDeep : kQuizBlue,
                borderRadius: BorderRadius.circular(18),
                border: listening ? Border.all(color: kQuizBlue, width: 2) : null,
                // em relevo (a base mais escura embaixo); ouvindo, fica "afundado"
                boxShadow: listening ? null : const [BoxShadow(color: kQuizBlueDark, offset: Offset(0, 5))],
              ),
              child: Center(
                child: listening
                    ? _LevelBars(level: level)
                    : const Icon(Icons.mic_rounded, size: 40, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Barrinhas que sobem com a voz, enquanto o aparelho ouve.
class _LevelBars extends StatelessWidget {
  const _LevelBars({required this.level});

  final ValueListenable<double> level;

  static const List<double> _shape = [0.45, 0.75, 1, 0.75, 0.45];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: level,
      builder: (context, value, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final k in _shape)
            AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 7,
              height: 8 + 36 * k * value,
              decoration: BoxDecoration(color: kQuizBlue, borderRadius: BorderRadius.circular(4)),
            ),
        ],
      ),
    );
  }
}

/// O "personagem" é o próprio vídeo da frase, falando no balão. Depois de falar a frase, cada
/// palavra fica verde (o aparelho ouviu) ou vermelha (não ouviu) — [marks].
class _Speech extends StatelessWidget {
  const _Speech({required this.item, required this.onSpeak, this.marks});

  final QuizItem item;
  final VoidCallback onSpeak;
  final List<SpokenWord>? marks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500, height: 1.5) ?? const TextStyle();
    final tokens = item.phrase.split(' ');
    final marks = this.marks?.length == tokens.length ? this.marks : null;
    final spans = <InlineSpan>[];
    for (final (i, token) in tokens.indexed) {
      if (i > 0) spans.add(const TextSpan(text: ' '));
      final word = token.toLowerCase().replaceAll(_notWord, '').replaceAll('’', "'");
      final highlight = word == item.word;
      final heard = marks?[i].heard;
      spans.add(TextSpan(
        text: token,
        style: heard != null
            ? base.copyWith(
                color: heard ? kQuizGreen : kQuizRed,
                fontWeight: FontWeight.w700,
                decoration: heard ? TextDecoration.none : TextDecoration.underline,
                decorationStyle: TextDecorationStyle.wavy,
                decorationColor: kQuizRed,
              )
            : highlight
            ? base.copyWith(
                color: kQuizPurple,
                fontWeight: FontWeight.w800,
                decoration: TextDecoration.underline,
                decorationStyle: TextDecorationStyle.dashed,
                decorationColor: kQuizPurple,
              )
            : base.copyWith(
                decoration: TextDecoration.underline,
                decorationStyle: TextDecorationStyle.dotted,
                decorationColor: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
      ));
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: kTileBorder, width: 3),
            color: kPanelHigh,
            image: item.videoId.isEmpty
                ? null
                : DecorationImage(
                    image: NetworkImage(thumbnailFor(item.videoId)),
                    fit: BoxFit.cover,
                    onError: (_, _) {}, // sem a miniatura, fica o círculo
                  ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: CustomPaint(
            painter: _BubblePainter(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 14, 10),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Ouvir',
                    onPressed: onSpeak,
                    icon: const Icon(Icons.volume_up_rounded, color: kQuizBlue, size: 30),
                  ),
                  const SizedBox(width: 2),
                  Expanded(child: Text.rich(TextSpan(children: spans))),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// O balão de fala, com a ponta para o vídeo.
class _BubblePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const tail = 12.0;
    final body = Path()
      ..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(tail, 0, size.width - tail, size.height), const Radius.circular(16)));
    final y = size.height * 0.62;
    final point = Path()
      ..moveTo(tail + 2, y - 10)
      ..lineTo(0, y + 8)
      ..lineTo(tail + 2, y + 4)
      ..close();
    final shape = Path.combine(PathOperation.union, body, point);
    canvas.drawPath(shape, Paint()..color = kPanel);
    canvas.drawPath(
      shape,
      Paint()
        ..color = kTileBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

const double _tileRow = 54; // altura de uma linha de fichas (com o espaço)

/// Onde a resposta é montada: as fichas escolhidas, sobre duas linhas.
class _AnswerArea extends StatelessWidget {
  const _AnswerArea({required this.tiles, required this.onTap});

  final List<(int, String)> tiles;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LinesPainter(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _tileRow * 2, minWidth: double.infinity),
        child: Wrap(
          spacing: 8,
          runSpacing: _tileRow - _Tile.height,
          children: [
            for (final (i, text) in tiles) _Tile(text: text, onTap: onTap == null ? null : () => onTap!(i)),
          ],
        ),
      ),
    );
  }
}

class _LinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = kTileBorder
      ..strokeWidth = 2;
    for (var y = _Tile.height + 4; y <= size.height + 1; y += _tileRow) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// As fichas para escolher; a que já foi usada deixa o lugar vazio.
class _Bank extends StatelessWidget {
  const _Bank({required this.tiles, required this.used, required this.onTap});

  final List<String> tiles;
  final Set<int> used;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 12,
        children: [
          for (final (i, text) in tiles.indexed)
            used.contains(i)
                ? _Tile(text: text, empty: true)
                : _Tile(text: text, onTap: onTap == null ? null : () => onTap!(i)),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.text, this.onTap, this.empty = false});

  static const double height = 48;

  final String text;
  final VoidCallback? onTap;

  /// O lugar da ficha que já foi usada.
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontSize: 18,
          color: empty ? Colors.transparent : null,
        );
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        decoration: BoxDecoration(
          color: empty ? kTileBorder.withValues(alpha: 0.55) : kPanelHigh,
          borderRadius: BorderRadius.circular(13),
          border: Border(
            top: BorderSide(color: empty ? Colors.transparent : kTileBorder, width: 2),
            left: BorderSide(color: empty ? Colors.transparent : kTileBorder, width: 2),
            right: BorderSide(color: empty ? Colors.transparent : kTileBorder, width: 2),
            bottom: BorderSide(color: empty ? Colors.transparent : kTileBorder, width: 4),
          ),
        ),
        // do tamanho da palavra (não da largura toda), centralizada na altura
        child: Center(widthFactor: 1, child: Text(text, style: style)),
      ),
    );
  }
}

class _BottomButton extends StatelessWidget {
  const _BottomButton({required this.label, required this.color, required this.onPressed});

  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: kQuizGreenDark,
            disabledBackgroundColor: kPanelHigh,
            disabledForegroundColor: kTileBorder,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 1),
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

/// Acertou ou errou: a resposta certa (ou o que foi ouvido), o vídeo da frase e o botão de
/// continuar.
class _Feedback extends StatelessWidget {
  const _Feedback({
    required this.correct,
    this.item,
    required this.title,
    required this.text,
    this.details = const [],
    required this.onContinue,
    required this.onOpenVideo,
  });

  final bool correct;
  final QuizItem? item;
  final String title;
  final String text;
  final List<String> details;
  final VoidCallback onContinue;
  final VoidCallback onOpenVideo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = correct ? kQuizGreen : kQuizRed;
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.13),
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(correct ? Icons.check_circle_rounded : Icons.cancel_rounded, color: color, size: 28),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(text, style: theme.textTheme.titleMedium?.copyWith(color: color)),
                for (final line in details) ...[
                  const SizedBox(height: 2),
                  Text(line, style: theme.textTheme.bodySmall?.copyWith(color: color.withValues(alpha: 0.85))),
                ],
                if (item != null && item!.videoId.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: color, padding: EdgeInsets.zero),
                      onPressed: onOpenVideo,
                      icon: const Icon(Icons.play_circle_outline, size: 20),
                      label: Text(
                        'Ver no vídeo${item!.videoTitle.isEmpty ? '' : ': ${item!.videoTitle}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _BottomButton(label: 'CONTINUAR', color: color, onPressed: onContinue),
        ],
      ),
    );
  }
}

/// Carregando, erro, lição completa ou quiz todo feito.
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.text,
    this.iconColor,
    this.button,
    this.onButton,
    this.secondary,
    this.onSecondary,
  });

  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String text;
  final String? button;
  final VoidCallback? onButton;
  final String? secondary;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon == null)
                    const SizedBox.square(dimension: 48, child: CircularProgressIndicator(color: kQuizGreen))
                  else
                    Icon(icon, size: 96, color: iconColor ?? kQuizGreen),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  if (secondary != null) ...[
                    const SizedBox(height: 12),
                    TextButton(onPressed: onSecondary, child: Text(secondary!)),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (button != null) _BottomButton(label: button!, color: kQuizGreen, onPressed: onButton),
      ],
    );
  }
}
