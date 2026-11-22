import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../app/services.dart';
import '../core/text.dart';
import '../quiz/quiz_session.dart';
import '../quiz/speaker.dart';
import '../youtube/video_id.dart';
import 'home_page.dart';
import 'theme.dart';

const Color kQuizGreen = Color(0xFF93D333);
const Color kQuizGreenDark = Color(0xFF14240A);
const Color kQuizRed = Color(0xFFFF5A5A);
const Color kQuizPurple = Color(0xFFCE82FF);
const Color kQuizBlue = Color(0xFF49C0F8);
const Color kTileBorder = Color(0xFF3A3A42);

final RegExp _notWord = RegExp(r"[^\p{L}'’\-]", unicode: true);

/// "Formar frases": traduzir a frase em inglês montando a tradução com as fichas, como no
/// Duolingo. As frases vêm das legendas do banco, das palavras que mais se repetem para as que
/// menos. [startAt]: praticar a partir de uma palavra escolhida (sem mudar onde o quiz parou).
class QuizPage extends StatefulWidget {
  const QuizPage({super.key, required this.services, this.startAt, this.speaker});

  final AppServices services;
  final int? startAt;

  /// A voz que lê a frase (os testes passam uma muda).
  final Speaker? speaker;

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  late final QuizSession quiz = QuizSession(api: widget.services.api, prefs: widget.services.prefs);
  late final Speaker speaker = widget.speaker ?? DeviceSpeaker();
  (int, int)? _spoken; // (lição, frase) já lida em voz alta

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
    final key = (quiz.lessons, quiz.step);
    if (item == null || quiz.loading || quiz.correct != null || key == _spoken) return;
    _spoken = key;
    unawaited(speaker.say(item.phrase));
  }

  void _openVideo(QuizItem item) {
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
              body = const _Message(
                icon: null,
                title: 'Analisando as frases das suas legendas…',
                text: 'As palavras que mais se repetem vêm primeiro.',
              );
            } else if (quiz.error.isNotEmpty) {
              body = _Message(
                icon: Icons.cloud_off_rounded,
                title: 'Não deu para carregar as frases',
                text: quiz.error,
                button: 'TENTAR DE NOVO',
                onButton: () => quiz.start(at: widget.startAt),
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
                title: 'Lição completa!',
                text: '${quiz.right} acertos em ${quiz.answered} respostas.',
                button: 'CONTINUAR',
                onButton: () => quiz.start(at: widget.startAt == null ? null : widget.startAt! + quiz.lessonSize),
                secondary: 'Voltar ao menu',
                onSecondary: () => Navigator.of(context).maybePop(),
              );
            } else {
              body = _Question(quiz: quiz, onSpeak: speaker.say, onOpenVideo: _openVideo);
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
  const _Question({required this.quiz, required this.onSpeak, required this.onOpenVideo});

  final QuizSession quiz;
  final Future<void> Function(String) onSpeak;
  final ValueChanged<QuizItem> onOpenVideo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = quiz.current!;
    final checked = quiz.correct != null;
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
                    const Icon(Icons.auto_awesome, color: kQuizPurple, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'PALAVRA FREQUENTE Nº ${thousands(item.position)}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: kQuizPurple,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Traduza esta frase:', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 20),
                _Speech(item: item, onSpeak: () => onSpeak(item.phrase)),
                const SizedBox(height: 10),
                Text(
                  '"${item.word}" aparece ${thousands(item.times)} vezes nas suas legendas',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 22),
                _AnswerArea(
                  tiles: [for (final i in quiz.picked) (i, item.tiles[i])],
                  onTap: checked ? null : quiz.unpick,
                ),
                const SizedBox(height: 30),
                _Bank(tiles: item.tiles, used: quiz.picked.toSet(), onTap: checked ? null : quiz.pick),
              ],
            ),
          ),
        ),
        if (!checked)
          _BottomButton(
            label: 'VERIFICAR',
            color: kQuizGreen,
            onPressed: quiz.canCheck ? quiz.check : null,
          )
        else
          _Feedback(
            correct: quiz.correct!,
            item: item,
            onContinue: quiz.next,
            onOpenVideo: () => onOpenVideo(item),
          ),
      ],
    );
  }
}

/// O "personagem" é o próprio vídeo da frase, falando no balão.
class _Speech extends StatelessWidget {
  const _Speech({required this.item, required this.onSpeak});

  final QuizItem item;
  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500, height: 1.5) ?? const TextStyle();
    final spans = <InlineSpan>[];
    for (final (i, token) in item.phrase.split(' ').indexed) {
      if (i > 0) spans.add(const TextSpan(text: ' '));
      final word = token.toLowerCase().replaceAll(_notWord, '').replaceAll('’', "'");
      final highlight = word == item.word;
      spans.add(TextSpan(
        text: token,
        style: highlight
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

/// Acertou ou errou: a resposta certa, o vídeo da frase e o botão de continuar.
class _Feedback extends StatelessWidget {
  const _Feedback({required this.correct, required this.item, required this.onContinue, required this.onOpenVideo});

  final bool correct;
  final QuizItem item;
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
                    Text(
                      correct ? 'Muito bem!' : 'Solução correta:',
                      style: theme.textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(item.translation, style: theme.textTheme.titleMedium?.copyWith(color: color)),
                if (!correct) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Esta frase volta no fim da lição.',
                    style: theme.textTheme.bodySmall?.copyWith(color: color.withValues(alpha: 0.85)),
                  ),
                ],
                if (item.videoId.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: color, padding: EdgeInsets.zero),
                      onPressed: onOpenVideo,
                      icon: const Icon(Icons.play_circle_outline, size: 20),
                      label: Text(
                        'Ver no vídeo${item.videoTitle.isEmpty ? '' : ': ${item.videoTitle}'}',
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
