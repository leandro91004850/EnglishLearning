import 'package:material_ui/material_ui.dart';

enum MenuAction { diagnostics, about }

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
  });

  final TextEditingController url;
  final String source;
  final bool compact;
  final ValueChanged<String> onSourceChanged;
  final VoidCallback onOpen;
  final VoidCallback onPaste;
  final ValueChanged<MenuAction> onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 8 : 12, 8, compact ? 2 : 6, 8),
      child: Row(
        children: [
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
            tooltip: 'Mais',
            icon: const Icon(Icons.more_vert),
            onSelected: onMenu,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: MenuAction.diagnostics,
                child: ListTile(leading: Icon(Icons.troubleshoot), title: Text('Diagnóstico')),
              ),
              PopupMenuItem(
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
