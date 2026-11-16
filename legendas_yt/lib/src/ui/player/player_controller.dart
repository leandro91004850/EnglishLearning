import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../core/log.dart';
import 'player_html.dart';

/// Estados do player do YouTube (`YT.PlayerState`).
abstract final class YtState {
  static const int unstarted = -1, ended = 0, playing = 1, paused = 2, buffering = 3, cued = 5;
}

/// Endereço da página do player.
///
/// O app.py explica: o player do YouTube exige página com endereço http (não
/// file://) e aberta por um NOME, não por IP — em 127.0.0.1 o YouTube recusa
/// alguns vídeos com "Este vídeo não está disponível". Por isso ele servia a
/// interface em http://localhost. Aqui a página vem da memória, carregada com
/// esse endereço como base: o player vê a mesma origem, sem servidor local.
const String playerBaseUrl = 'http://localhost/';

/// O player (um WebView com o IFrame API) e onde o vídeo está.
class PlayerController extends ChangeNotifier {
  PlayerController() {
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  late final Timer _ticker;
  WebViewController? _web;
  bool _booted = false;
  bool _disposed = false;

  String? videoId;
  bool ready = false;
  int state = YtState.unstarted;
  double duration = 0;
  double rate = 1;

  /// Código de erro do player (2, 5, 100, 101, 150, 152, 153; -1 sem o script do YouTube).
  int? error;

  double _time = 0;
  DateTime _timeAt = DateTime.now();

  /// Onde o vídeo está (s). Enquanto toca, avança 10 vezes por segundo.
  final ValueNotifier<double> position = ValueNotifier(0);

  /// O vídeo chegou ao fim.
  VoidCallback? onEnded;

  bool get hasVideo => videoId != null;
  bool get playing => state == YtState.playing || state == YtState.buffering;

  WebViewController get web => _web ??= _create();

  WebViewController _create() {
    final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true, // no iPhone, sem isso o vídeo abre em tela cheia e a legenda some
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }
    final controller = WebViewController.fromPlatformCreationParams(params);
    _quiet(controller.setJavaScriptMode(JavaScriptMode.unrestricted));
    _quiet(controller.addJavaScriptChannel('LegendasBridge', onMessageReceived: (m) => _onMessage(m.message)));
    _quiet(controller.setNavigationDelegate(NavigationDelegate(
      onNavigationRequest: _onNavigation,
      onWebResourceError: (e) {
        if (e.isForMainFrame ?? false) Log.warning('Player: ${e.errorCode} ${e.description}');
      },
    )));
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      _quiet(controller.setBackgroundColor(const Color(0xFF000000)));
      _quiet(controller.setOverScrollMode(WebViewOverScrollMode.never));
    }
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      _quiet(platform.setMediaPlaybackRequiresUserGesture(false));
    } else if (platform is WebKitWebViewController) {
      _quiet(platform.setInspectable(kDebugMode));
    }
    return controller;
  }

  static void _quiet(Future<void> f) {
    f.catchError((Object e) => Log.warning('Player: $e'));
  }

  /// Abre o vídeo em [start] segundos. Sem [autoplay], fica parado na capa.
  void load(String id, {double start = 0, bool autoplay = true}) {
    final s = start.isFinite && start > 0 ? start : 0.0;
    videoId = id;
    error = null;
    state = YtState.unstarted;
    duration = 0;
    _setTime(s);
    if (_web == null || !_booted) {
      _loadPage(id, s, autoplay);
    } else {
      _js('legendas.load(${jsonEncode(id)}, $s, $autoplay)');
    }
    _notify();
  }

  /// Recarrega a página do player no mesmo ponto (depois de um erro).
  void reload() {
    final id = videoId;
    if (id == null) return;
    error = null;
    _loadPage(id, position.value, true);
    _notify();
  }

  void _loadPage(String id, double start, bool autoplay) {
    _booted = false;
    ready = false;
    _quiet(web.loadHtmlString(
      playerHtml(videoId: id, start: start, autoplay: autoplay),
      baseUrl: playerBaseUrl,
    ));
  }

  void seekTo(double seconds) {
    final s = seconds.isFinite ? math.max(0.0, seconds) : 0.0;
    _setTime(s);
    _js('legendas.seek($s)');
  }

  void play() => _js('legendas.play()');
  void pause() => _js('legendas.pause()');
  void togglePlay() => _js('legendas.toggle()');

  void setRate(double value) {
    rate = value;
    _js('legendas.rate($value)');
    _notify();
  }

  void _js(String code) {
    final web = _web;
    if (web == null || !_booted) return;
    _quiet(web.runJavaScript(code));
  }

  void _setTime(double s) {
    _time = s;
    _timeAt = DateTime.now();
    position.value = s;
  }

  // Entre um aviso da página e outro, a posição segue o relógio. Pequenos
  // recuos (atraso do aviso) são ignorados, para a legenda não piscar.
  void _advance(double t) {
    final p = position.value;
    if (t < p && p - t < 0.35) return;
    position.value = t;
  }

  void _tick() {
    if (state != YtState.playing) return;
    final elapsed = DateTime.now().difference(_timeAt).inMicroseconds / 1e6;
    var t = _time + math.min(elapsed, 1.5) * rate;
    if (duration > 0) t = math.min(t, duration);
    _advance(t);
  }

  void _onMessage(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (decoded is! Map) return;
    final m = decoded;
    switch (m['t']) {
      case 'boot':
        _booted = true;
      case 'ready':
        ready = true;
        _notify();
      case 'time':
        if (m['v'] == videoId) _onTime(m);
      case 'error':
        if (m['v'] != videoId) return;
        error = (m['code'] as num?)?.toInt() ?? -1;
        Log.warning('Player do YouTube: erro $error em $videoId');
        _notify();
      case 'log':
        Log.info('Player: ${m['m']}');
    }
  }

  void _onTime(Map<dynamic, dynamic> m) {
    double number(Object? v, [double fallback = 0]) => v is num && v.isFinite ? v.toDouble() : fallback;
    final c = number(m['c']);
    final d = number(m['d']);
    final s = (m['s'] as num?)?.toInt() ?? YtState.unstarted;
    final r = number(m['r'], 1);
    final ended = s == YtState.ended && state != YtState.ended;
    final changed = s != state || d != duration || r != rate || !ready;
    final wasPlaying = state == YtState.playing;
    state = s;
    duration = d;
    rate = r > 0 ? r : 1;
    ready = true;
    _time = c;
    _timeAt = DateTime.now();
    if (s == YtState.playing && wasPlaying) {
      _advance(c);
    } else {
      position.value = c;
    }
    if (changed) _notify();
    if (ended) onEnded?.call();
  }

  FutureOr<NavigationDecision> _onNavigation(NavigationRequest request) {
    final url = request.url;
    if (!request.isMainFrame || url.startsWith(playerBaseUrl) || url.startsWith('about:')) {
      return NavigationDecision.navigate;
    }
    // link para fora (logo do YouTube, "Assistir no YouTube"...): abre no navegador
    final uri = Uri.tryParse(url);
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
    }
    return NavigationDecision.prevent;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.cancel();
    position.dispose();
    super.dispose();
  }
}

/// O player na tela.
class YoutubePlayerView extends StatelessWidget {
  const YoutubePlayerView({super.key, required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: controller.web);
}
