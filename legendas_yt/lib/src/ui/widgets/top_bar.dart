import 'package:material_ui/material_ui.dart';

enum MenuAction { server, diagnostics, about }

const Map<String, String> sourceLabels = {'auto': 'Auto', 'en': 'EN', 'pt': 'PT'};

/// Campo do link, idioma da legenda original e botão Abrir.
class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.url,
    required this.source,
    required this.compact,
    required this.onSourceChanged,
    required this.onOpen,
    required this.onPaste,
    required this.onMenu,
    this.serverProblem = false,
    this.onBack,
  });

  final TextEditingController url;
  final String source;
  final bool compact;
  final ValueChanged<String> onSourceChanged;
  final VoidCallback onOpen;
  final VoidCallback onPaste;
  final ValueChanged<MenuAction> onMenu;

  /// A API (ou o banco de dados dela) com problema: ponto vermelho no menu.
  final bool serverProblem;

  /// Volta para o menu inicial (sem ele, a seta não aparece).
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(onBack != null ? 0 : (compact ? 8 : 12), 8, compact ? 2 : 6, 8),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              tooltip: 'Menu',
              visualDensity: compact ? VisualDensity.compact : null,
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
            ),
          Expanded(
            child: TextField(
              controller: url,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => onOpen(),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: scheme.surfaceContainerHigh,
                hintText: compact ? 'Link do YouTube' : 'Cole o link do YouTube (ou o ID do vídeo)',
                prefixIcon: compact ? null : const Icon(Icons.link, size: 20),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: url,
                  builder: (context, value, _) => value.text.isEmpty
                      ? IconButton(
                          tooltip: 'Colar',
                          onPressed: onPaste,
                          icon: const Icon(Icons.content_paste, size: 20),
                        )
                      : IconButton(
                          tooltip: 'Limpar',
                          onPressed: url.clear,
                          icon: const Icon(Icons.close, size: 20),
                        ),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.fromLTRB(compact ? 16 : 0, 12, 0, 12),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _SourceMenu(source: source, compact: compact, onChanged: onSourceChanged),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: onOpen,
            style: compact ? FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14)) : null,
            child: const Text('Abrir'),
          ),
          PopupMenuButton<MenuAction>(
            tooltip: serverProblem ? 'Mais (servidor com problema)' : 'Mais',
            icon: Badge(isLabelVisible: serverProblem, smallSize: 9, child: const Icon(Icons.more_vert)),
            onSelected: onMenu,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: MenuAction.server,
                child: ListTile(
                  leading: Badge(
                    isLabelVisible: serverProblem,
                    smallSize: 8,
                    child: const Icon(Icons.dns_outlined),
                  ),
                  title: const Text('Servidor'),
                ),
              ),
              const PopupMenuItem(
                value: MenuAction.diagnostics,
                child: ListTile(leading: Icon(Icons.troubleshoot), title: Text('Diagnóstico')),
              ),
              const PopupMenuItem(
                value: MenuAction.about,
                child: ListTile(leading: Icon(Icons.info_outline), title: Text('Sobre')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourceMenu extends StatelessWidget {
  const _SourceMenu({required this.source, required this.compact, required this.onChanged});

  final String source;
  final bool compact;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'Legenda original',
      initialValue: source,
      onSelected: onChanged,
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'auto',
          child: ListTile(
            title: Text('Automático'),
            subtitle: Text('Prefere legenda feita por pessoas, em inglês ou português'),
          ),
        ),
        PopupMenuItem(
          value: 'en',
          child: ListTile(title: Text('Inglês'), subtitle: Text('Traduz para português')),
        ),
        PopupMenuItem(
          value: 'pt',
          child: ListTile(title: Text('Português'), subtitle: Text('Traduz para inglês')),
        ),
      ],
      child: Container(
        padding: EdgeInsets.fromLTRB(compact ? 12 : 10, 8, compact ? 4 : 10, 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!compact) ...[
              Icon(Icons.translate, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
            ],
            Text(sourceLabels[source] ?? 'Auto', style: Theme.of(context).textTheme.labelLarge),
            Icon(Icons.arrow_drop_down, size: 18, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
