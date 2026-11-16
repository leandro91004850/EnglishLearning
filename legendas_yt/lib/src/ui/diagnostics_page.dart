import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/diagnostics.dart';
import '../core/log.dart';
import 'theme.dart';

/// O `--diagnostico` do app.py dentro do app, mais as últimas linhas do registro.
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key, required this.diagnostics, this.url});

  final Diagnostics diagnostics;

  /// Link do vídeo aberto, para testar as legendas dele também.
  final String? url;

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  final List<String> _lines = [];
  bool _running = false;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _lines.clear();
    });
    await for (final line in widget.diagnostics.run(url: widget.url)) {
      if (!mounted) return;
      setState(() => _lines.add(line));
    }
    if (mounted) setState(() => _running = false);
  }

  void _copy() {
    final text = [..._lines, '', '--- registro ---', ...Log.lines].join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copiado.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = kMono.copyWith(fontSize: 12, height: 1.45, color: theme.colorScheme.onSurface);
    final log = Log.lines.reversed.take(200).join('\n');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnóstico'),
        actions: [IconButton(tooltip: 'Copiar tudo', onPressed: _copy, icon: const Icon(Icons.copy_all))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Testa os tradutores (Google nos dois modos e a reserva MyMemory) e, se houver um vídeo '
            'aberto, as legendas dele no YouTube.',
            style: theme.textTheme.bodyMedium,
          ),
          if (widget.url != null) ...[
            const SizedBox(height: 6),
            Text('Vídeo: ${widget.url}', style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _running ? null : _run,
              icon: _running
                  ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow),
              label: Text(_running ? 'Testando…' : 'Rodar diagnóstico'),
            ),
          ),
          if (_lines.isNotEmpty) ...[
            const SizedBox(height: 16),
            _Box(child: SelectableText(_lines.join('\n'), style: mono)),
          ],
          const SizedBox(height: 24),
          Text('Registro (mais recentes primeiro) · ${Log.fileName}', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          _Box(child: SelectableText(log.isEmpty ? '(vazio)' : log, style: mono)),
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}
