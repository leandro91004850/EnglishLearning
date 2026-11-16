import 'dart:convert';

/// Página do player: o IFrame API do YouTube ocupando a tela toda (o
/// `ui/index.html` do app.py, só com o vídeo; a legenda é desenhada pelo
/// Flutter por cima). A página avisa o app pelo canal `LegendasBridge`:
///  - `{t: "time", v, c, d, s, r}` 4 vezes por segundo: vídeo, posição (s),
///    duração (s), estado (YT.PlayerState) e velocidade;
///  - `{t: "ready"}`, `{t: "error", code}`, `{t: "boot"}`, `{t: "log", m}`.
/// O app manda comandos chamando `legendas.load/seek/play/pause/toggle/rate`.
String playerHtml({required String videoId, required double start, required bool autoplay}) {
  final initial = jsonEncode({'v': videoId, 'start': start, 'autoplay': autoplay});
  return '''<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<style>
  html, body { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background: #000; }
  #player, iframe { position: fixed; top: 0; left: 0; width: 100%; height: 100%; border: 0; }
</style>
</head>
<body>
<div id="player"></div>
<script>
(function () {
  "use strict";
  var initial = $initial;
  var current = initial.v;
  var player = null, ready = false, pending = null;
  var lastValue = -1, lastAt = 0;
  var captionsHidden = false;

  function send(msg) {
    try { window.LegendasBridge.postMessage(JSON.stringify(msg)); } catch (e) {}
  }
  function now() { return (window.performance && performance.now()) || Date.now(); }
  window.addEventListener("error", function (e) { send({t: "log", m: String(e.message || e)}); });

  // O getCurrentTime() do IFrame API só muda umas 4 vezes por segundo; entre uma
  // mudança e outra, enquanto toca, a posição avança no relógio.
  function currentTime() {
    var c = player.getCurrentTime() || 0, t = now();
    if (c !== lastValue) { lastValue = c; lastAt = t; return c; }
    if (player.getPlayerState() === 1) {
      return c + Math.min((t - lastAt) / 1000, 1) * (player.getPlaybackRate() || 1);
    }
    return c;
  }

  // O YouTube às vezes liga a legenda dele sozinho (ex.: vídeo em inglês com o
  // aparelho em português), por baixo da do app. Desliga uma vez por vídeo, assim
  // que o módulo de legendas carrega; se a pessoa ligar no botão CC, fica ligada.
  function hideYouTubeCaptions() {
    if (captionsHidden || !ready) return;
    var modules = [];
    try { modules = player.getOptions() || []; } catch (e) {}
    if (modules.indexOf("captions") < 0 && modules.indexOf("cc") < 0) return;
    try { player.setOption("captions", "track", {}); } catch (e) {}
    try { player.unloadModule("captions"); } catch (e) {}
    try { player.unloadModule("cc"); } catch (e) {}
    captionsHidden = true;
  }

  function report() {
    if (!ready || !player || typeof player.getCurrentTime !== "function") return;
    hideYouTubeCaptions();
    send({t: "time", v: current, c: currentTime(), d: player.getDuration() || 0,
          s: player.getPlayerState(), r: player.getPlaybackRate() || 1});
  }

  window.onYouTubeIframeAPIReady = function () {
    player = new YT.Player("player", {
      width: "100%", height: "100%",
      videoId: initial.v,
      playerVars: {
        autoplay: initial.autoplay ? 1 : 0,
        start: Math.floor(initial.start || 0),
        playsinline: 1, rel: 0, fs: 0, iv_load_policy: 3, cc_load_policy: 0,
        enablejsapi: 1, origin: window.location.origin, hl: "pt-BR"
      },
      events: {
        onReady: function () {
          ready = true;
          send({t: "ready", v: current});
          if (pending) { var p = pending; pending = null; window.legendas.load(p.v, p.start, p.autoplay); }
          report();
        },
        onStateChange: function () { report(); },
        onApiChange: function () { hideYouTubeCaptions(); },
        onPlaybackRateChange: function () { report(); },
        onError: function (e) { send({t: "error", v: current, code: e.data}); }
      }
    });
  };

  window.legendas = {
    load: function (v, start, autoplay) {
      current = v;
      lastValue = -1;
      captionsHidden = false;
      if (!ready) {
        if (player) pending = {v: v, start: start, autoplay: autoplay};
        else initial = {v: v, start: start, autoplay: autoplay};
        return;
      }
      var opts = {videoId: v, startSeconds: start || 0};
      if (autoplay) player.loadVideoById(opts); else player.cueVideoById(opts);
    },
    seek: function (s) { if (ready) { player.seekTo(s, true); report(); } },
    play: function () { if (ready) player.playVideo(); },
    pause: function () { if (ready) player.pauseVideo(); },
    toggle: function () {
      if (!ready) return;
      var s = player.getPlayerState();
      if (s === 1 || s === 3) player.pauseVideo(); else player.playVideo();
    },
    rate: function (r) { if (ready) { player.setPlaybackRate(r); report(); } }
  };

  setInterval(report, 250);
  var tag = document.createElement("script");
  tag.src = "https://www.youtube.com/iframe_api";
  tag.onerror = function () { send({t: "error", v: current, code: -1}); };
  document.head.appendChild(tag);
  send({t: "boot"});
})();
</script>
</body>
</html>''';
}
