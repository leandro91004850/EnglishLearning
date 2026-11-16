import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/services.dart';
import '../app/session.dart';
import '../core/cue.dart';
import '../core/log.dart';
import '../core/subtitles.dart';
import '../core/text.dart';
import '../data/history.dart';
import '../data/prefs.dart';
import '../youtube/video_id.dart';
import 'diagnostics_page.dart';
import 'player/player_controller.dart';
import 'theme.dart';
import 'widgets/history_list.dart';
import 'widgets/player_toolbar.dart';
import 'widgets/status_line.dart';
import 'widgets/subtitle_overlay.dart';
import 'widgets/top_bar.dart';
import 'widgets/transcript_list.dart';
import 'window_control.dart';

/// Largura a partir da qual a lista fica ao lado do vídeo.
const double kWideLayout = 900;

/// Abaixo desta altura a interface esconde o resto e mostra só o vídeo (como o
/// app.py faz abaixo de uns 720×460).
const double kVideoOnlyHeight = 460;

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.services});

  final AppServices services;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late final SubtitleSession session = widget.services.session;
  late final History history = widget.services.history;
  late final Prefs prefs = widget.services.prefs;

  final TextEditingController _url = TextEditingController();
  final PlayerController _player = PlayerController();
  final GlobalKey _stageKey = GlobalKey();
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late final AppLifecycleListener _lifecycle;

  /// (fala atual, ela ainda está no tempo dela)
  final ValueNotifier<(int, bool)> _cue = ValueNotifier((-1, false));
  final ValueNotifier<int> _current = ValueNotifier(-1);

  String _source = 'auto';
  bool _fullscreen = false;
  int _focusSent = -1;
  DateTime _progressAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _player.position.addListener(_sync);
    _player.onEnded = _onEnded;
    session.addListener(_sync);
    _lifecycle = AppLifecycleListener(
      onHide: history.save,
      onPause: history.save,
      onDetach: history.save,
      onExitRequested: () async {
        history.save(); // guarda onde o último vídeo parou
        return AppExitResponse.exit;
      },
    );
    WindowControl.listen((on) {
      if (mounted && on != _fullscreen) setState(() => _fullscreen = on);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) WindowControl.lockPortraitOnPhone(phone: _phone);
    });
    // reabre o último vídeo assistido, parado onde ficou
    final last = history.latest;
    if (last != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _open(
            last.link,
            source: last.source,
            keepPlace: true,
            autoplay: false,
            start: last.resumeAt,
            why: 'último assistido, ao abrir o app',
          );
        }
      });
    } else {
      _tabs.index = 1;
    }
  }

  @override
  void dispose() {
    history.save();
    session.removeListener(_sync);
    _lifecycle.dispose();
    _player.dispose();
    _tabs.dispose();
    _url.dispose();
    _cue.dispose();
    _current.dispose();
    super.dispose();
  }

  // ---- vídeo e legenda ----

  /// Abre o link (ou ID). [keepPlace]: aberto pela lista de recentes.
  /// [why] vai para o registro (de onde veio o pedido para abrir).
  void _open(
    String text, {
    String? source,
    bool keepPlace = false,
    bool autoplay = true,
    double? start,
    String why = 'link',
  }) {
    final src = normalizeSource(source ?? _source);
    final vid = extractVideoId(text);
    final saved = vid == null ? null : history.find(vid);
    final result = session.load(text, source: src, keepPlace: keepPlace);
    if (!result.ok) {
      _snack(result.error!);
      return;
    }
    final id = result.videoId!;
    Log.info('Abrindo $id ($why)');
    _focusSent = -1;
    setState(() => _source = src);
    if (_tabs.index != 0) _tabs.animateTo(0); // mostra as falas do vídeo
    if (extractVideoId(_url.text) != id) _url.text = watchUrlFor(id);
    if (id != _player.videoId) {
      _player.load(id, start: start ?? startTimeFromUrl(text) ?? saved?.resumeAt ?? 0, autoplay: autoplay);
    }
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _openTyped() {
    final text = _url.text.trim();
    if (text.isEmpty) {
      _snack('Cole um link do YouTube.');
      return;
    }
    _open(text);
  }

  void _openItem(HistoryItem item, {String why = 'lista de recentes'}) {
    _open(item.link, source: item.source, keepPlace: true, start: item.resumeAt, why: why);
  }

  void _retry() {
    final vid = session.videoId;
    if (vid != null) _open(vid, source: _source, keepPlace: true, why: 'tentar de novo');
  }

  void _changeSource(String value) {
    setState(() => _source = value);
    final vid = session.videoId;
    if (vid != null) _open(vid, source: value, keepPlace: true, why: 'troca do idioma da legenda');
  }

  void _removeItem(HistoryItem item) {
    history.remove(item.id);
    unawaited(widget.services.cache.prune({for (final x in history.items) x.id}));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;
    _url.text = text;
    if (extractVideoId(text) != null) _open(text);
  }

  /// Acompanha o vídeo: fala atual, trecho a traduzir primeiro e posição salva.
  void _sync() {
    final t = _player.position.value;
    final cues = session.cues;
    final i = cues.isEmpty || _player.videoId != session.videoId ? -1 : cueIndexAt(cues, t);
    _cue.value = (i, i >= 0 && t <= cues[i].end + 0.3);
    _current.value = i;
    if (i >= 0 && i != _focusSent) {
      _focusSent = i;
      session.focus(session.job, i);
    }
    final vid = _player.videoId;
    if (vid != null && _player.playing && _player.duration > 0) {
      final now = DateTime.now();
      if (now.difference(_progressAt) >= const Duration(seconds: 2)) {
        _progressAt = now;
        session.progress(vid, t, _player.duration);
      }
    }
  }

  /// O vídeo terminou: segue para o de baixo na lista de recentes.
  /// O player do YouTube às vezes avisa "terminou" antes do fim (trecho
  /// bloqueado, falha de rede); aí o app fica onde está.
  void _onEnded() {
    final vid = _player.videoId;
    if (vid == null) return;
    final pos = _player.position.value;
    final dur = _player.duration;
    final atEnd = dur > 0 && pos >= dur - 5;
    Log.info('Vídeo $vid terminou em ${formatTime(pos)} de ${formatTime(dur)}'
        '${atEnd ? '' : ' — antes do fim, não segue para o próximo'}');
    if (!atEnd) return;
    session.progress(vid, dur, dur);
    history.save();
    final items = history.items;
    final i = items.indexWhere((x) => x.id == vid);
    if (i >= 0 && i + 1 < items.length) _openItem(items[i + 1], why: 'o anterior terminou');
  }

  void _seekTo(double seconds) {
    _player.seekTo(seconds);
    if (!_player.playing) _player.play();
  }

  /// -1: fala anterior (ou o começo da atual, se já passou um pouco dele);
  /// 0: repete a atual; 1: próxima.
  void _seekCue(int delta) {
    final cues = session.cues;
    if (cues.isEmpty || !_player.hasVideo) return;
    final t = _player.position.value;
    final i = cueIndexAt(cues, t);
    var target = switch (delta) {
      0 => math.max(i, 0),
      < 0 => i >= 0 && t - cues[i].start > 1.5 ? i : i - 1,
      _ => i + 1,
    };
    target = target.clamp(0, cues.length - 1);
    _seekTo(cues[target].start);
  }

  bool get _phone => MediaQuery.sizeOf(context).shortestSide < 600;

  Future<void> _setFullscreen(bool on) async {
    if (on == _fullscreen) return;
    final phone = _phone;
    setState(() => _fullscreen = on);
    await WindowControl.setFullScreen(on, phone: phone);
  }

  void _toggleFullscreen() => _setFullscreen(!_fullscreen);

  // ---- teclado (desktop) ----

  bool get _typing {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null && (ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (_typing) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final repeat = event is KeyRepeatEvent;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _seekCue(-1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _seekCue(1);
    } else if (repeat) {
      return KeyEventResult.ignored;
    } else if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      _player.togglePlay();
    } else if (key == LogicalKeyboardKey.keyR) {
      _seekCue(0);
    } else if (key == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
    } else if (key == LogicalKeyboardKey.escape && _fullscreen) {
      _setFullscreen(false);
    } else if (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.add || key == LogicalKeyboardKey.numpadAdd) {
      prefs.subSize += 2;
    } else if (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract) {
      prefs.subSize -= 2;
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _onMenu(MenuAction action) {
    switch (action) {
      case MenuAction.diagnostics:
        final vid = session.videoId;
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => DiagnosticsPage(
            diagnostics: widget.services.diagnostics(),
            url: vid == null ? null : watchUrlFor(vid),
          ),
        ));
      case MenuAction.about:
        showAboutDialog(
          context: context,
          applicationName: 'Legendas YT',
          applicationVersion: '1.0.0',
          applicationIcon: const Icon(Icons.subtitles, size: 40),
          children: const [
            SizedBox(height: 8),
            Text(
              'Abre o vídeo do YouTube, baixa a legenda original e mostra, junto com o vídeo, a fala '
              'original e a tradução (inglês ⇄ português).\n\n'
              'Tradução: Google Tradutor gratuito; quando ele falha, a reserva MyMemory '
              '(até 5.000 caracteres por dia).\n\n'
              'Atalhos: espaço tocar/pausar · ← → fala anterior/próxima · R repetir · F tela cheia · + − tamanho da legenda.',
            ),
          ],
        );
    }
  }

  // ---- layout ----

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _setFullscreen(false);
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: _fullscreen ? Colors.black : kBackground,
          body: LayoutBuilder(
            builder: (context, box) {
              if (_fullscreen || box.maxHeight < kVideoOnlyHeight) return _videoOnly();
              return SafeArea(child: box.maxWidth >= kWideLayout ? _wide(box) : _stacked(box));
            },
          ),
        ),
      ),
    );
  }

  Widget _wide(BoxConstraints box) {
    final side = (box.maxWidth * 0.32).clamp(320.0, 440.0);
    return Column(
      children: [
        _topBar(compact: false),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Center(child: AspectRatio(aspectRatio: 16 / 9, child: _stage())),
                      ),
                    ),
                    const SizedBox(height: 4),
                    _toolbar(compact: false),
                    StatusLine(session: session, history: history),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(width: side, child: _sidePanel()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stacked(BoxConstraints box) {
    final videoHeight = math.min(box.maxWidth * 9 / 16, box.maxHeight * 0.42);
    return Column(
      children: [
        _topBar(compact: true),
        SizedBox(
          height: videoHeight,
          child: Center(child: AspectRatio(aspectRatio: 16 / 9, child: _stage())),
        ),
        _toolbar(compact: true),
        StatusLine(session: session, history: history),
        const Divider(),
        Expanded(child: _sidePanel()),
      ],
    );
  }

  Widget _videoOnly() {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        children: [
          Center(child: AspectRatio(aspectRatio: 16 / 9, child: _stage())),
          if (_player.hasVideo)
            Positioned(
              top: 8,
              right: 8,
              child: SafeArea(
                child: IconButton.filledTonal(
                  tooltip: _fullscreen ? 'Sair da tela cheia (Esc)' : 'Tela cheia (F)',
                  onPressed: _toggleFullscreen,
                  icon: Icon(_fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _topBar({required bool compact}) => TopBar(
        url: _url,
        source: _source,
        compact: compact,
        onSourceChanged: _changeSource,
        onOpen: _openTyped,
        onPaste: _paste,
        onMenu: _onMenu,
      );

  Widget _toolbar({required bool compact}) => PlayerToolbar(
        player: _player,
        prefs: prefs,
        compact: compact,
        fullscreen: _fullscreen,
        onPrevious: () => _seekCue(-1),
        onRepeat: () => _seekCue(0),
        onNext: () => _seekCue(1),
        onFullscreen: _toggleFullscreen,
      );

  Widget _sidePanel() {
    return Column(
      children: [
        ListenableBuilder(
          listenable: Listenable.merge([session, history]),
          builder: (context, _) => TabBar(
            controller: _tabs,
            tabs: [
              Tab(text: session.cues.isEmpty ? 'Falas' : 'Falas (${session.cues.length})'),
              Tab(text: history.isEmpty ? 'Recentes' : 'Recentes (${history.items.length})'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              TranscriptList(
                session: session,
                current: _current,
                onSeek: (i) => _seekTo(session.cues[i].start),
                onRetry: _retry,
              ),
              ListenableBuilder(
                listenable: session,
                builder: (context, _) => HistoryList(
                  history: history,
                  currentId: session.videoId,
                  onOpen: _openItem,
                  onRemove: _removeItem,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// O vídeo com a legenda por cima. Tem uma chave global para o WebView não ser
  /// recriado quando o layout muda (girar a tela, tela cheia, redimensionar).
  Widget _stage() {
    return KeyedSubtree(
      key: _stageKey,
      child: ListenableBuilder(
        listenable: _player,
        builder: (context, _) {
          final error = _player.error;
          return Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              if (_player.hasVideo) YoutubePlayerView(controller: _player) else const _EmptyVideo(),
              if (_player.hasVideo) Positioned.fill(child: IgnorePointer(child: _overlay())),
              if (error != null)
                _PlayerError(
                  code: error,
                  onRetry: _player.reload,
                  onOpenYouTube: () {
                    final vid = _player.videoId;
                    if (vid != null) {
                      unawaited(launchUrl(Uri.parse(watchUrlFor(vid)), mode: LaunchMode.externalApplication));
                    }
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _overlay() {
    return ValueListenableBuilder<(int, bool)>(
      valueListenable: _cue,
      builder: (context, cue, _) => ListenableBuilder(
        listenable: Listenable.merge([session, prefs]),
        builder: (context, _) {
          final (i, showing) = cue;
          final cues = session.cues;
          if (!showing || i < 0 || i >= cues.length) return const SizedBox.shrink();
          return SubtitleOverlay(
            original: cues[i].text,
            translation: i < session.translations.length ? session.translations[i] : null,
            show: prefs.show,
            baseSize: prefs.subSize,
          );
        },
      ),
    );
  }
}

class _EmptyVideo extends StatelessWidget {
  const _EmptyVideo();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.subtitles_outlined, size: 44, color: theme.colorScheme.primary),
            const SizedBox(height: 10),
            Text('Cole um link do YouTube e toque em Abrir', style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              'A legenda original aparece com a tradução (inglês ⇄ português), no tempo do vídeo.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerError extends StatelessWidget {
  const _PlayerError({required this.code, required this.onRetry, required this.onOpenYouTube});

  final int code;
  final VoidCallback onRetry;
  final VoidCallback onOpenYouTube;

  String get message => switch (code) {
        2 => 'O player do YouTube recusou o ID deste vídeo.',
        5 => 'O player do YouTube falhou neste aparelho (erro 5).',
        100 => 'Vídeo não encontrado: foi removido ou é privado.',
        101 || 150 => 'O dono deste vídeo não deixa ele tocar fora do YouTube.',
        152 || 153 => 'O YouTube recusou o player incorporado (erro $code).',
        -1 => 'Não consegui carregar o player do YouTube. Confira a internet.',
        _ => 'O player do YouTube deu erro ($code).',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: const Color(0xE6000000),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error, size: 36),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Tentar de novo')),
                  FilledButton.icon(
                    onPressed: onOpenYouTube,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Abrir no YouTube'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
