import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../app/services.dart';
import '../core/text.dart';
import 'app_actions.dart';
import 'archived_page.dart';
import 'home_page.dart';
import 'quiz_page.dart';
import 'words_page.dart';

const Color kVideosColor = Color(0xFFFF6A55);
const Color kQuizColor = Color(0xFF93D333);
const Color kWordsColor = Color(0xFF49C0F8);

/// O menu inicial: Vídeos, Lições e Palavras mais usadas, com os números das suas legendas.
class MenuPage extends StatefulWidget {
  const MenuPage({super.key, required this.services});

  final AppServices services;

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  late final AppLifecycleListener _lifecycle;
  WordStats? _stats;
  QuizItem? _next; // a próxima frase do quiz
  int _archived = 0; // frases arquivadas (fora das lições)
  bool _loading = true;

  AppServices get services => widget.services;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: services.history.save,
      onPause: services.history.save,
      onDetach: services.history.save,
      onExitRequested: () async {
        await services.shutdown(); // manda para a API onde o último vídeo parou
        return AppExitResponse.exit;
      },
    );
    unawaited(_load());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Os números das legendas e a próxima frase do quiz (na abertura e ao voltar de uma tela).
  Future<void> _load() async {
    await services.ready;
    WordStats? stats;
    QuizItem? next;
    int? archived;
    try {
      stats = await services.api.words(count: 6);
      final batch = await services.api.quiz(start: services.prefs.quizPos, count: 1);
      next = batch.items.isEmpty ? null : batch.items.first;
      archived = batch.archived;
    } on ApiFailure {
      // o aviso do servidor já aparece no alto do menu
    }
    if (!mounted) return;
    setState(() {
      _stats = stats ?? _stats;
      _next = next;
      _archived = archived ?? _archived;
      _loading = false;
    });
  }

  Future<void> _go(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) unawaited(_load());
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 5 || hour >= 18) return 'Boa noite!';
    return hour < 12 ? 'Bom dia!' : 'Boa tarde!';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([services.history, services.prefs]),
          builder: (context, _) {
            final stats = _stats;
            final last = services.history.latest;
            final position = services.prefs.quizPos;
            final total = stats?.quizItems ?? 0;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.asset('assets/icone.png', width: 56, height: 56),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$_greeting Vamos praticar?', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text('Inglês com os vídeos que você assiste', style: muted),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                ValueListenableBuilder<String>(
                  valueListenable: services.apiStatus,
                  builder: (context, problem, _) => problem.isEmpty
                      ? const SizedBox.shrink()
                      : _Warning(text: problem, onTap: () => openServer(context, services)),
                ),
                _Numbers(
                  items: [
                    (Icons.smart_display_outlined, services.history.items.length, 'vídeos'),
                    (Icons.subtitles_outlined, stats?.phrases, 'falas'),
                    (Icons.translate, stats?.total, 'palavras'),
                  ],
                  loading: _loading,
                ),
                const SizedBox(height: 18),
                _MenuCard(
                  color: kVideosColor,
                  icon: Icons.smart_display_rounded,
                  title: 'Vídeos',
                  text: 'Assista com a fala original e a tradução, no tempo do vídeo.',
                  footer: Text(
                    last == null
                        ? 'Cole um link do YouTube para começar.'
                        : 'Continuar: ${last.title.isNotEmpty ? last.title : last.id}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: kVideosColor, fontWeight: FontWeight.w600),
                  ),
                  onTap: () => _go(HomePage(services: services)),
                ),
                _MenuCard(
                  color: kQuizColor,
                  icon: Icons.school_rounded,
                  title: 'Lições',
                  text: 'Exercícios sorteados com as frases dos seus vídeos: monte a tradução e repita em '
                      'voz alta.',
                  footer: total == 0
                      ? null
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _next == null
                                        ? 'Você fez todas as ${thousands(total)} frases!'
                                        : 'Próxima palavra: "${_next!.word}"',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: kQuizColor, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Text(
                                  '${thousands(position)} de ${thousands(total)}',
                                  style: theme.textTheme.bodySmall?.copyWith(color: kQuizColor),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: (position / total).clamp(0.0, 1.0),
                                minHeight: 6,
                                color: kQuizColor,
                                backgroundColor: kQuizColor.withValues(alpha: 0.15),
                              ),
                            ),
                            if (_archived > 0)
                              TextButton.icon(
                                onPressed: () => _go(ArchivedPage(services: services)),
                                style: TextButton.styleFrom(
                                  foregroundColor: kQuizColor,
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.archive_outlined, size: 18),
                                label: Text(
                                  _archived == 1 ? '1 frase arquivada' : '${thousands(_archived)} frases arquivadas',
                                ),
                              ),
                          ],
                        ),
                  onTap: () => _go(QuizPage(services: services)),
                ),
                _MenuCard(
                  color: kWordsColor,
                  icon: Icons.bar_chart_rounded,
                  title: 'Palavras mais usadas',
                  text: 'O ranking das palavras em inglês das suas legendas; toque numa para praticar.',
                  footer: stats == null || stats.words.isEmpty
                      ? null
                      : Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final w in stats.words.take(5))
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                decoration: BoxDecoration(
                                  color: kWordsColor.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${w.word} ${thousands(w.times)}',
                                  style: theme.textTheme.labelMedium?.copyWith(color: kWordsColor),
                                ),
                              ),
                          ],
                        ),
                  onTap: () => _go(WordsPage(services: services)),
                ),
                const SizedBox(height: 6),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: () => openServer(context, services),
                      icon: const Icon(Icons.dns_outlined, size: 18),
                      label: const Text('Servidor'),
                    ),
                    TextButton.icon(
                      onPressed: () => openDiagnostics(context, services),
                      icon: const Icon(Icons.troubleshoot, size: 18),
                      label: const Text('Diagnóstico'),
                    ),
                    TextButton.icon(
                      onPressed: () => showAbout(context),
                      icon: const Icon(Icons.info_outline, size: 18),
                      label: const Text('Sobre'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.text,
    required this.onTap,
    this.footer,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String text;
  final Widget? footer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withValues(alpha: 0.20), color.withValues(alpha: 0.05)],
              ),
              border: Border.all(color: color.withValues(alpha: 0.45), width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 10, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 4))],
                    ),
                    child: Icon(icon, color: Colors.black.withValues(alpha: 0.8), size: 30),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          text,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        if (footer != null) ...[const SizedBox(height: 10), footer!],
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: color),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Os números das legendas: vídeos, falas e palavras.
class _Numbers extends StatelessWidget {
  const _Numbers({required this.items, required this.loading});

  final List<(IconData, int?, String)> items;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        for (final (i, (icon, value, label)) in items.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(height: 4),
                  Text(
                    value != null ? thousands(value) : (loading ? '…' : '—'),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: error.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: error.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.dns_outlined, size: 18, color: error),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: error))),
            ],
          ),
        ),
      ),
    );
  }
}
