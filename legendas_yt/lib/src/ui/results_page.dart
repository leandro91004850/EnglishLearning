import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../app/services.dart';
import '../core/text.dart';
import 'quiz_page.dart';
import 'theme.dart';

enum _Order { wrong, right, recent }

/// O ranking das palavras nas lições: quantas vezes você acertou e errou cada uma, e quando foi o
/// último teste (a tabela resultados_palavras, na API). Tocar numa palavra pratica de novo.
class ResultsPage extends StatefulWidget {
  const ResultsPage({super.key, required this.services});

  final AppServices services;

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  late Future<WordResults> _future = widget.services.api.results();
  _Order _order = _Order.wrong;

  void _reload() => setState(() => _future = widget.services.api.results());

  /// A revisão: as erradas ainda não revisadas primeiro, depois as com mais erros e há mais tempo sem
  /// revisar.
  Future<void> _review() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => QuizPage(services: widget.services, review: true),
    ));
    if (mounted) _reload();
  }

  Future<void> _practice(WordResult result) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => QuizPage(services: widget.services, startAt: result.item),
    ));
    if (mounted) _reload();
  }

  /// As palavras na ordem escolhida; "erradas" e "acertadas" só com pelo menos um erro ou acerto.
  static List<WordResult> _sorted(List<WordResult> words, _Order order) {
    int recent(WordResult a, WordResult b) =>
        (b.lastTest ?? DateTime(0)).compareTo(a.lastTest ?? DateTime(0));
    final list = switch (order) {
      _Order.wrong => [for (final w in words) if (w.wrong > 0) w],
      _Order.right => [for (final w in words) if (w.right > 0) w],
      _Order.recent => List.of(words),
    };
    list.sort((a, b) {
      final c = switch (order) {
        _Order.wrong => b.wrong.compareTo(a.wrong) != 0 ? b.wrong.compareTo(a.wrong) : a.rate.compareTo(b.rate),
        _Order.right => b.right.compareTo(a.right) != 0 ? b.right.compareTo(a.right) : b.rate.compareTo(a.rate),
        _Order.recent => 0,
      };
      if (c != 0) return c;
      final r = recent(a, b);
      return r != 0 ? r : a.word.compareTo(b.word);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Seus resultados')),
      body: FutureBuilder<WordResults>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final error = snapshot.error;
          final results = snapshot.data;
          if (error != null || results == null) {
            return _Empty(
              icon: Icons.cloud_off_rounded,
              title: 'Não deu para carregar os resultados',
              text: error is ApiFailure ? error.message : '$error',
              button: OutlinedButton(onPressed: _reload, child: const Text('Tentar de novo')),
            );
          }
          if (results.words.isEmpty) {
            return const _Empty(
              icon: Icons.emoji_events_outlined,
              title: 'Nenhum teste ainda',
              text: 'Faça uma lição: cada frase respondida entra aqui, na palavra dela, com o acerto ou o erro '
                  'e a data do teste.',
            );
          }
          final words = _sorted(results.words, _order);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _Summary(results: results),
              const SizedBox(height: 14),
              if (results.toReview > 0)
                _ReviewButton(total: results.toReview, pending: results.pending, onTap: _review)
              else
                Text(
                  'Nada para revisar agora: as palavras que você erra entram na revisão, e as que você acerta de '
                  'novo voltam um dia depois do último teste.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                ),
              const SizedBox(height: 14),
              SegmentedButton<_Order>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: _Order.wrong, label: Text('Erradas')),
                  ButtonSegment(value: _Order.right, label: Text('Acertadas')),
                  ButtonSegment(value: _Order.recent, label: Text('Recentes')),
                ],
                selected: {_order},
                onSelectionChanged: (s) => setState(() => _order = s.first),
              ),
              const SizedBox(height: 8),
              if (words.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _order == _Order.wrong ? 'Nenhuma palavra errada até agora.' : 'Nenhuma palavra acertada ainda.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              for (final (i, w) in words.indexed)
                _ResultRow(rank: i + 1, result: w, onPractice: w.item == null ? null : () => _practice(w)),
            ],
          );
        },
      ),
    );
  }
}

/// O botão da revisão, com quantas palavras e quantas ainda não foram revisadas.
class _ReviewButton extends StatelessWidget {
  const _ReviewButton({required this.total, required this.pending, required this.onTap});

  final int total;
  final int pending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: kQuizOrange,
              foregroundColor: const Color(0xFF2A1700),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.8),
            ),
            icon: const Icon(Icons.replay_rounded),
            label: Text('REVISAR ${thousands(total)} ${total == 1 ? 'PALAVRA' : 'PALAVRAS'}'),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          pending > 0
              ? 'Primeiro ${pending == 1 ? 'a errada que você ainda não revisou' : 'as ${thousands(pending)} erradas que você ainda não revisou'}; '
                  'depois as com mais erros e há mais tempo sem revisar.'
              : 'As com mais erros e há mais tempo sem revisar primeiro.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Os totais: acertos, erros, a taxa de acerto e o último teste.
class _Summary extends StatelessWidget {
  const _Summary({required this.results});

  final WordResults results;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = results.right + results.wrong;
    final rate = total == 0 ? 0 : (results.right * 100 / total).round();
    final last = results.lastTest;
    Widget box(String value, String label, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(14)),
            child: Column(
              children: [
                Text(value, style: theme.textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w800)),
                Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            box(thousands(results.right), 'acertos', kQuizGreen),
            const SizedBox(width: 8),
            box(thousands(results.wrong), 'erros', kQuizRed),
            const SizedBox(width: 8),
            box('$rate%', 'de acerto', kQuizOrange),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${results.words.length == 1 ? '1 palavra testada' : '${thousands(results.words.length)} palavras testadas'}'
          '${last == null ? '' : ' · último teste ${dayAndTime(last)}'}',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.rank, required this.result, required this.onPractice});

  final int rank;
  final WordResult result;
  final VoidCallback? onPractice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final last = result.lastTest;
    return InkWell(
      onTap: onPractice,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text('$rank', textAlign: TextAlign.center, style: muted?.copyWith(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          result.word,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text('✓ ${thousands(result.right)}', style: muted?.copyWith(color: kQuizGreen)),
                      const SizedBox(width: 10),
                      Text('✗ ${thousands(result.wrong)}', style: muted?.copyWith(color: kQuizRed)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 6,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch, // as cores ocupam a altura toda
                        children: [
                          if (result.right > 0) Expanded(flex: result.right, child: const ColoredBox(color: kQuizGreen)),
                          if (result.wrong > 0) Expanded(flex: result.wrong, child: const ColoredBox(color: kQuizRed)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        result.lastRight ? Icons.check_circle_rounded : Icons.cancel_rounded,
                        size: 14,
                        color: result.lastRight ? kQuizGreen : kQuizRed,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(last == null ? 'sem data' : 'último teste ${dayAndTime(last)}', style: muted),
                      ),
                      Text('${(result.rate * 100).round()}% de acerto', style: muted),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: onPractice == null ? 'A frase desta palavra não está nas lições' : 'Praticar de novo',
              onPressed: onPractice,
              icon: Icon(
                Icons.play_circle_fill_rounded,
                size: 30,
                color: onPractice == null ? theme.disabledColor : kQuizGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.text, this.button});

  final IconData icon;
  final String title;
  final String text;
  final Widget? button;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (button != null) ...[const SizedBox(height: 14), button!],
          ],
        ),
      ),
    );
  }
}
