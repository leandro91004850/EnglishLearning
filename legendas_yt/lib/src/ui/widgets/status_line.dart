import 'package:material_ui/material_ui.dart';

import '../../app/session.dart';
import '../../data/history.dart';

/// Título do vídeo e a mensagem de estado (o `setStatus` do app.py), com a
/// barra de progresso da tradução.
class StatusLine extends StatelessWidget {
  const StatusLine({super.key, required this.session, required this.history});

  final SubtitleSession session;
  final History history;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([session, history]),
      builder: (context, _) {
        final vid = session.videoId;
        if (vid == null) return const SizedBox(height: 8);
        final item = history.find(vid);
        final title = item?.title ?? '';
        final meta = session.meta;
        final error = session.statusError;
        final progress = session.toTranslate > 0 ? session.translated / session.toTranslate : null;

        final Widget icon;
        if (error) {
          icon = Icon(Icons.error_outline, size: 18, color: scheme.error);
        } else if (session.busy) {
          icon = const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2));
        } else {
          icon = Icon(Icons.check_circle_outline, size: 18, color: scheme.primary);
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title.isNotEmpty)
                Text(
                  item!.author.isNotEmpty ? '$title · ${item.author}' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(padding: const EdgeInsets.only(top: 1), child: icon),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      session.status.isEmpty ? 'Abrindo…' : session.status,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: error ? scheme.error : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (meta != null && meta.generated)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Tooltip(
                        message: 'Legenda gerada automaticamente pelo YouTube',
                        child: Chip(
                          label: const Text('automática'),
                          visualDensity: VisualDensity.compact,
                          labelStyle: theme.textTheme.labelSmall,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                ],
              ),
              if (session.busy && progress != null && progress < 1)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: LinearProgressIndicator(value: progress, minHeight: 2),
                ),
            ],
          ),
        );
      },
    );
  }
}
