import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/session.dart';
import '../../core/text.dart';
import '../theme.dart';

/// A lista de falas: original + tradução, com a fala atual destacada e
/// acompanhando o vídeo. Tocar numa fala leva o vídeo até ela.
class TranscriptList extends StatefulWidget {
  const TranscriptList({
    super.key,
    required this.session,
    required this.current,
    required this.onSeek,
    required this.onRetry,
  });

  final SubtitleSession session;

  /// Índice da fala atual (-1 antes da primeira).
  final ValueListenable<int> current;
  final ValueChanged<int> onSeek;
  final VoidCallback onRetry;

  @override
  State<TranscriptList> createState() => _TranscriptListState();
}

class _TranscriptListState extends State<TranscriptList> {
  final ScrollController _scroll = ScrollController();
  final Map<int, BuildContext> _rows = {};
  DateTime _userScrolledAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _followed = -1;

  @override
  void initState() {
    super.initState();
    widget.current.addListener(_onCurrent);
    // ao aparecer (abrir o app, voltar para esta aba), já mostra a fala atual
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final i = widget.current.value;
      if (mounted && i >= 0) {
        _followed = i;
        _scrollTo(i, animate: false);
      }
    });
  }

  @override
  void didUpdateWidget(TranscriptList old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) {
      old.current.removeListener(_onCurrent);
      widget.current.addListener(_onCurrent);
    }
  }

  @override
  void dispose() {
    widget.current.removeListener(_onCurrent);
    _scroll.dispose();
    super.dispose();
  }

  void _onCurrent() {
    final i = widget.current.value;
    if (i < 0 || i == _followed) return;
    // a pessoa rolou a lista há pouco: não puxa de volta
    if (DateTime.now().difference(_userScrolledAt) < const Duration(seconds: 4)) return;
    _followed = i;
    _scrollTo(i, animate: true);
  }

  void _scrollTo(int index, {required bool animate, int attempts = 12}) {
    if (!mounted) return;
    if (!_scroll.hasClients) {
      // as falas acabaram de chegar e a lista ainda não foi montada
      if (attempts > 0) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollTo(index, animate: false, attempts: attempts - 1),
        );
      }
      return;
    }
    final row = _rows[index];
    if (row != null && row.mounted) {
      Scrollable.ensureVisible(
        row,
        alignment: 0.3,
        duration: animate ? const Duration(milliseconds: 250) : Duration.zero,
        curve: Curves.easeOut,
      );
      return;
    }
    if (attempts == 0) return;
    // A fala ainda não foi montada. As linhas têm alturas diferentes, então uma
    // estimativa só pelo índice erra longe: anda a partir das falas que estão
    // montadas agora, na direção da desejada, e confere de novo no próximo quadro.
    final position = _scroll.position;
    final built = [
      for (final MapEntry(key: i, value: ctx) in _rows.entries)
        if (ctx.mounted) i,
    ]..sort();
    final avg = _averageRowHeight();
    final double target;
    if (built.isEmpty) {
      target = index * avg - position.viewportDimension * 0.3;
    } else if (index > built.last) {
      target = position.pixels + (index - built.last) * avg + position.viewportDimension * 0.5;
    } else {
      target = position.pixels - (built.first - index) * avg - position.viewportDimension * 0.5;
    }
    _scroll.jumpTo(target.clamp(position.minScrollExtent, position.maxScrollExtent));
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollTo(index, animate: false, attempts: attempts - 1),
    );
  }

  double _averageRowHeight() {
    var total = 0.0;
    var n = 0;
    for (final row in _rows.values) {
      if (!row.mounted) continue;
      final box = row.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        total += box.size.height;
        n++;
      }
    }
    return n == 0 ? 60 : total / n;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final s = widget.session;
        final cues = s.cues;
        if (cues.isEmpty) return _placeholder(theme, s);
        return NotificationListener<UserScrollNotification>(
          onNotification: (n) {
            if (n.direction != ScrollDirection.idle) {
              _userScrolledAt = DateTime.now();
              _followed = -1;
            }
            return false;
          },
          child: ValueListenableBuilder<int>(
            valueListenable: widget.current,
            builder: (context, current, _) => ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: cues.length,
              itemBuilder: (context, i) => _RowRef(
                index: i,
                rows: _rows,
                child: _CueRow(
                  time: cues[i].start,
                  original: cues[i].text,
                  translation: i < s.translations.length ? s.translations[i] : null,
                  active: i == current,
                  onTap: () {
                    _userScrolledAt = DateTime.fromMillisecondsSinceEpoch(0);
                    widget.onSeek(i);
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _placeholder(ThemeData theme, SubtitleSession s) {
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final Widget content;
    if (s.videoId == null) {
      content = Text('Abra um vídeo para ver as falas aqui.', style: muted, textAlign: TextAlign.center);
    } else if (s.busy) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(height: 14),
          Text(s.status.isEmpty ? 'Buscando legendas…' : s.status, style: muted, textAlign: TextAlign.center),
        ],
      );
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.subtitles_off_outlined, size: 36, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(s.status, style: muted, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: widget.onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar de novo'),
          ),
        ],
      );
    }
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: content));
  }
}

/// Anota o contexto de cada fala montada, para a lista rolar até ela.
class _RowRef extends StatefulWidget {
  const _RowRef({required this.index, required this.rows, required this.child});

  final int index;
  final Map<int, BuildContext> rows;
  final Widget child;

  @override
  State<_RowRef> createState() => _RowRefState();
}

class _RowRefState extends State<_RowRef> {
  @override
  void initState() {
    super.initState();
    widget.rows[widget.index] = context;
  }

  @override
  void didUpdateWidget(_RowRef old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && identical(old.rows[old.index], context)) {
      old.rows.remove(old.index);
    }
    widget.rows[widget.index] = context;
  }

  @override
  void dispose() {
    if (identical(widget.rows[widget.index], context)) widget.rows.remove(widget.index);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _CueRow extends StatelessWidget {
  const _CueRow({
    required this.time,
    required this.original,
    required this.translation,
    required this.active,
    required this.onTap,
  });

  final double time;
  final String original;
  final String? translation;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyMedium!;
    final tr = translation;
    return Material(
      color: active ? scheme.primary.withValues(alpha: 0.14) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: active ? scheme.primary : Colors.transparent, width: 3),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(11, 8, 14, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 54,
                child: Text(
                  formatTime(time),
                  style: kMono.copyWith(
                    fontSize: 12,
                    height: 1.7,
                    color: active ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      original,
                      style: body.copyWith(
                        color: active ? Colors.white : scheme.onSurface,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tr ?? '…',
                      style: body.copyWith(
                        color: tr == null
                            ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
                            : kTranslation.withValues(alpha: active ? 1 : 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
