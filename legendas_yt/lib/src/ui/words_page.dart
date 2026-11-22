import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../app/services.dart';
import '../core/text.dart';
import 'quiz_page.dart';
import 'theme.dart';

const Color _blue = Color(0xFF49C0F8);

/// O ranking das palavras em inglês que mais se repetem nas legendas do banco (a análise da API).
/// Tocar numa palavra abre o quiz na frase dela.
class WordsPage extends StatefulWidget {
  const WordsPage({super.key, required this.services});

  final AppServices services;

  @override
  State<WordsPage> createState() => _WordsPageState();
}

class _WordsPageState extends State<WordsPage> {
  late Future<WordStats> _future = widget.services.api.words(count: 300);

  void _practice(WordStat word) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => QuizPage(services: widget.services, startAt: word.item),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: const Text('Palavras mais usadas')),
      body: FutureBuilder<WordStats>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final error = snapshot.error;
          final stats = snapshot.data;
          if (error != null || stats == null || stats.words.isEmpty) {
            final message = error is ApiFailure
                ? error.message
                : (stats?.dbMessage.isNotEmpty ?? false)
                    ? stats!.dbMessage
                    : 'Ainda não há falas traduzidas no banco: abra alguns vídeos primeiro.';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => setState(() => _future = widget.services.api.words(count: 300)),
                      child: const Text('Tentar de novo'),
                    ),
                  ],
                ),
              ),
            );
          }
          final top = stats.words.first.times;
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: stats.words.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Text(
                    '${thousands(stats.total)} palavras diferentes em ${thousands(stats.phrases)} falas das suas '
                    'legendas. Toque numa palavra para praticar com a frase dela.',
                    style: muted,
                  ),
                );
              }
              final word = stats.words[i - 1];
              return InkWell(
                onTap: word.item == null ? null : () => _practice(word),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: Text('$i', textAlign: TextAlign.center, style: muted?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(word.word, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                                const Spacer(),
                                Text('${thousands(word.times)} vezes', style: muted),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: word.times / top,
                                minHeight: 6,
                                color: _blue,
                                backgroundColor: kPanelHigh,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text('em ${thousands(word.phrases)} falas', style: muted),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: word.item == null ? 'Sem frase para praticar' : 'Praticar',
                        onPressed: word.item == null ? null : () => _practice(word),
                        icon: const Icon(Icons.play_circle_fill_rounded, color: kQuizGreen, size: 32),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
