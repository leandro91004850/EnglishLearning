import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../app/services.dart';
import '../core/text.dart';
import 'home_page.dart';
import 'theme.dart';

const Color _green = Color(0xFF93D333);

/// As frases arquivadas nas lições (elas não aparecem mais lá). Restaurar traz a frase de volta.
class ArchivedPage extends StatefulWidget {
  const ArchivedPage({super.key, required this.services});

  final AppServices services;

  @override
  State<ArchivedPage> createState() => _ArchivedPageState();
}

class _ArchivedPageState extends State<ArchivedPage> {
  List<ArchivedPhrase>? _phrases; // null: carregando
  String _error = '';
  final Set<int> _restoring = {};

  ApiClient get _api => widget.services.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _phrases = null;
      _error = '';
    });
    try {
      final phrases = await _api.archived();
      if (mounted) setState(() => _phrases = phrases);
    } on ApiFailure catch (e) {
      if (mounted) {
        setState(() {
          _phrases = const [];
          _error = e.message;
        });
      }
    }
  }

  Future<void> _restore(ArchivedPhrase phrase) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _restoring.add(phrase.id));
    try {
      await _api.restore(phrase.id);
      if (!mounted) return;
      setState(() {
        _restoring.remove(phrase.id);
        _phrases = [for (final p in _phrases ?? const <ArchivedPhrase>[]) if (p.id != phrase.id) p];
      });
      messenger.showSnackBar(const SnackBar(content: Text('Frase restaurada: ela volta a aparecer nas lições.')));
    } on ApiFailure catch (e) {
      if (!mounted) return;
      setState(() => _restoring.remove(phrase.id));
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _openVideo(ArchivedPhrase phrase) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => HomePage(services: widget.services, startVideo: phrase.videoId, startAt: phrase.start),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final phrases = _phrases;
    final Widget body;
    if (phrases == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error.isNotEmpty) {
      body = _Centered(
        icon: Icons.cloud_off_rounded,
        title: 'Não deu para carregar as frases arquivadas',
        text: _error,
        button: OutlinedButton(onPressed: _load, child: const Text('Tentar de novo')),
      );
    } else if (phrases.isEmpty) {
      body = const _Centered(
        icon: Icons.archive_outlined,
        title: 'Nenhuma frase arquivada',
        text: 'Nas lições, toque no ícone de arquivar ao lado de "Palavra frequente" para tirar das lições '
            'uma frase que você não quer fazer.',
      );
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: phrases.length + 1,
        separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 4 : 10),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                '${phrases.length == 1 ? '1 frase fica' : '${thousands(phrases.length)} frases ficam'} fora das '
                'lições. Restaurar traz a frase de volta.',
                style: muted,
              ),
            );
          }
          final phrase = phrases[i - 1];
          final when = phrase.archivedAt?.toLocal();
          final busy = _restoring.contains(phrase.id);
          return Container(
            decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(phrase.phrase, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(phrase.translation, style: theme.textTheme.bodyMedium?.copyWith(color: _green)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        [
                          if (phrase.videoTitle.isNotEmpty) phrase.videoTitle,
                          if (when != null) 'arquivada em ${_date(when)}',
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    ),
                    if (phrase.videoId.isNotEmpty)
                      IconButton(
                        tooltip: 'Ver no vídeo',
                        onPressed: () => _openVideo(phrase),
                        icon: const Icon(Icons.play_circle_outline),
                      ),
                    busy
                        ? const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : TextButton.icon(
                            onPressed: () => _restore(phrase),
                            icon: const Icon(Icons.unarchive_outlined, size: 20),
                            label: const Text('Restaurar'),
                          ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    }
    return Scaffold(appBar: AppBar(title: const Text('Frases arquivadas')), body: body);
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _Centered extends StatelessWidget {
  const _Centered({required this.icon, required this.title, required this.text, this.button});

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
