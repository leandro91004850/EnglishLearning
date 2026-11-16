import 'package:material_ui/material_ui.dart';

import '../../data/prefs.dart';
import '../player/player_controller.dart';

const List<double> playbackRates = [0.5, 0.75, 0.9, 1, 1.25, 1.5];

String rateLabel(double r) => '${r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toString()}×';

/// Controles de estudo abaixo do vídeo: fala anterior / repetir / próxima,
/// velocidade, o que mostrar sobre o vídeo, tamanho da legenda e tela cheia.
class PlayerToolbar extends StatelessWidget {
  const PlayerToolbar({
    super.key,
    required this.player,
    required this.prefs,
    required this.compact,
    required this.fullscreen,
    required this.onPrevious,
    required this.onRepeat,
    required this.onNext,
    required this.onFullscreen,
  });

  final PlayerController player;
  final Prefs prefs;
  final bool compact;
  final bool fullscreen;
  final VoidCallback onPrevious;
  final VoidCallback onRepeat;
  final VoidCallback onNext;
  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([player, prefs]),
      builder: (context, _) {
        final enabled = player.hasVideo;
        final row = Row(
          children: [
            IconButton(
              tooltip: 'Fala anterior (←)',
              onPressed: enabled ? onPrevious : null,
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            IconButton(
              tooltip: 'Repetir a fala (R)',
              onPressed: enabled ? onRepeat : null,
              icon: const Icon(Icons.replay_rounded),
            ),
            IconButton.filledTonal(
              tooltip: player.playing ? 'Pausar (espaço)' : 'Tocar (espaço)',
              onPressed: enabled ? player.togglePlay : null,
              icon: Icon(player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
            ),
            IconButton(
              tooltip: 'Próxima fala (→)',
              onPressed: enabled ? onNext : null,
              icon: const Icon(Icons.skip_next_rounded),
            ),
            PopupMenuButton<double>(
              tooltip: 'Velocidade',
              enabled: enabled,
              initialValue: player.rate,
              onSelected: player.setRate,
              itemBuilder: (_) => [
                for (final r in playbackRates) PopupMenuItem(value: r, child: Text(rateLabel(r))),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Text(rateLabel(player.rate), style: Theme.of(context).textTheme.labelLarge),
              ),
            ),
            if (compact)
              IconButton(
                tooltip: 'Legenda: o que mostrar e tamanho',
                onPressed: () => showSubtitleSettings(context, prefs),
                icon: const Icon(Icons.closed_caption_outlined),
              )
            else ...[
              const SizedBox(width: 8),
              ShowModeSelector(prefs: prefs),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Legenda menor (−)',
                onPressed: prefs.subSize > Prefs.minSubSize ? () => prefs.subSize -= 2 : null,
                icon: const Icon(Icons.text_decrease),
              ),
              IconButton(
                tooltip: 'Legenda maior (+)',
                onPressed: prefs.subSize < Prefs.maxSubSize ? () => prefs.subSize += 2 : null,
                icon: const Icon(Icons.text_increase),
              ),
            ],
            IconButton(
              tooltip: fullscreen ? 'Sair da tela cheia (Esc)' : 'Tela cheia (F)',
              onPressed: enabled ? onFullscreen : null,
              icon: Icon(fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
            ),
          ],
        );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 10),
          child: row,
        );
      },
    );
  }
}

/// Ambas / Tradução / Original.
class ShowModeSelector extends StatelessWidget {
  const ShowModeSelector({super.key, required this.prefs});

  final Prefs prefs;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ShowMode>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity(horizontal: -2, vertical: -2)),
      segments: [
        for (final m in ShowMode.values) ButtonSegment(value: m, label: Text(m.label)),
      ],
      selected: {prefs.show},
      onSelectionChanged: (s) => prefs.show = s.first,
    );
  }
}

/// No celular: o que mostrar sobre o vídeo e o tamanho da legenda numa folha.
Future<void> showSubtitleSettings(BuildContext context, Prefs prefs) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sobre o vídeo', style: theme.textTheme.titleSmall),
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: ShowModeSelector(prefs: prefs)),
                const SizedBox(height: 20),
                Text('Tamanho da legenda: ${prefs.subSize}', style: theme.textTheme.titleSmall),
                Slider(
                  value: prefs.subSize.toDouble(),
                  min: Prefs.minSubSize.toDouble(),
                  max: Prefs.maxSubSize.toDouble(),
                  divisions: (Prefs.maxSubSize - Prefs.minSubSize) ~/ 2,
                  label: '${prefs.subSize}',
                  onChanged: (v) => prefs.subSize = v.round(),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
