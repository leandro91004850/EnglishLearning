import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/text.dart';
import '../../data/history.dart';
import '../../youtube/video_id.dart';

/// Os vídeos recentes. Tocar abre o vídeo (ele fica no lugar dele na lista);
/// tocar e segurar levanta o vídeo, que pode ser arrastado para cima ou para
/// baixo (no lugar das setas do app.py); o × tira da lista — só sem o banco de
/// dados: com ele, a lista tem todos os vídeos de lá ([History.canRemove]).
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
        return ReorderableListView.builder(
          padding: const EdgeInsets.only(bottom: 6),
          // segurar em qualquer ponto do vídeo começa o arraste (também no computador)
          buildDefaultDragHandles: false,
          header: items.length > 1
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                  child: Row(
                    children: [
                      Icon(Icons.swap_vert, size: 16, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Toque e segure um vídeo para arrastar e mudar a ordem.',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox(height: 6),
          itemCount: items.length,
          onReorderStart: (_) => HapticFeedback.mediumImpact(),
          onReorderEnd: (_) => HapticFeedback.selectionClick(),
          onReorderItem: history.reorder,
          proxyDecorator: _lifted,
          itemBuilder: (context, i) {
            final item = items[i];
            return ReorderableDelayedDragStartListener(
              key: ValueKey(item.id),
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: _HistoryTile(
                  item: item,
                  current: item.id == currentId,
                  onOpen: () => onOpen(item),
                  onRemove: history.canRemove ? () => onRemove(item) : null,
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// O vídeo que está sendo arrastado fica "levantado" sobre os outros.
  static Widget _lifted(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = Curves.easeOut.transform(animation.value);
        final scheme = Theme.of(context).colorScheme;
        return Transform.scale(
          scale: 1 + 0.03 * t,
          child: Material(
            elevation: 10 * t,
            shadowColor: Colors.black,
            color: Color.lerp(scheme.surface, scheme.surfaceContainerHighest, t),
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: child,
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
    required this.onOpen,
    this.onRemove,
  });

  final HistoryItem item;
  final bool current;
  final VoidCallback onOpen;

  /// O ×; sem ele (com o banco de dados), o botão não aparece.
  final VoidCallback? onRemove;

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
              if (onRemove != null)
                IconButton(
                  visualDensity: compact,
                  tooltip: 'Tirar da lista',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close, size: 20),
                )
              else
                const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}
