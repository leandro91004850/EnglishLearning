import 'package:material_ui/material_ui.dart';

import '../../core/text.dart';
import '../../data/history.dart';
import '../../youtube/video_id.dart';

/// Os vídeos recentes. Tocar abre o vídeo (ele fica no lugar dele na lista);
/// as setas sobem ou descem o vídeo; o × tira da lista.
class HistoryList extends StatelessWidget {
  const HistoryList({
    super.key,
    required this.history,
    required this.currentId,
    required this.onOpen,
    required this.onRemove,
  });

  final History history;
  final String? currentId;
  final ValueChanged<HistoryItem> onOpen;
  final ValueChanged<HistoryItem> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: history,
      builder: (context, _) {
        final items = history.items;
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Os vídeos que você abrir aparecem aqui, com o ponto onde parou.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 2),
          itemBuilder: (context, i) => _HistoryTile(
            item: items[i],
            current: items[i].id == currentId,
            canUp: i > 0,
            canDown: i < items.length - 1,
            onOpen: () => onOpen(items[i]),
            onUp: () => history.move(items[i].id, -1),
            onDown: () => history.move(items[i].id, 1),
            onRemove: () => onRemove(items[i]),
          ),
        );
      },
    );
  }
}

String timeAgo(int at, {DateTime? now}) {
  final when = DateTime.fromMillisecondsSinceEpoch(at * 1000);
  final d = (now ?? DateTime.now()).difference(when);
  if (d.inMinutes < 1) return 'agora';
  if (d.inMinutes < 60) return 'há ${d.inMinutes} min';
  if (d.inHours < 24) return 'há ${d.inHours} h';
  if (d.inDays == 1) return 'ontem';
  if (d.inDays < 30) return 'há ${d.inDays} dias';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(when.day)}/${two(when.month)}/${when.year}';
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.item,
    required this.current,
    required this.canUp,
    required this.canDown,
    required this.onOpen,
    required this.onUp,
    required this.onDown,
    required this.onRemove,
  });

  final HistoryItem item;
  final bool current;
  final bool canUp;
  final bool canDown;
  final VoidCallback onOpen;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final details = [
      if (item.author.isNotEmpty) item.author,
      if (item.at > 0) timeAgo(item.at),
    ].join(' · ');
    final where = item.dur > 0 ? '${formatTime(item.pos)} / ${formatTime(item.dur)}' : '';
    const compact = VisualDensity(horizontal: -4, vertical: -4);

    return Material(
      color: current ? scheme.primary.withValues(alpha: 0.12) : Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 112,
                  height: 63,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        thumbnailFor(item.id),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: scheme.surfaceContainerHighest,
                          child: Icon(Icons.smart_display_outlined, color: scheme.onSurfaceVariant),
                        ),
                      ),
                      if (item.progress > 0)
                        Align(
                          alignment: Alignment.bottomLeft,
                          child: FractionallySizedBox(
                            widthFactor: item.progress,
                            child: Container(height: 3, color: scheme.primary),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title.isNotEmpty ? item.title : item.id,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: current ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    if (details.isNotEmpty)
                      Text(details, maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
                    if (where.isNotEmpty) Text(where, style: small),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: compact,
                    tooltip: 'Subir na lista',
                    onPressed: canUp ? onUp : null,
                    icon: const Icon(Icons.keyboard_arrow_up),
                  ),
                  IconButton(
                    visualDensity: compact,
                    tooltip: 'Descer na lista',
                    onPressed: canDown ? onDown : null,
                    icon: const Icon(Icons.keyboard_arrow_down),
                  ),
                ],
              ),
              IconButton(
                visualDensity: compact,
                tooltip: 'Tirar da lista',
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
