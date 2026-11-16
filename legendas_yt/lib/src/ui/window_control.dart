import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/log.dart';

/// Tela cheia (o `toggle_fullscreen` do app.py). No celular esconde as barras
/// do sistema e, no telefone, deita a tela; no macOS põe a janela em tela cheia
/// pelo canal que o `MainFlutterWindow.swift` atende.
abstract final class WindowControl {
  static const MethodChannel _channel = MethodChannel('legendas_yt/window');

  static const List<DeviceOrientation> _portrait = [DeviceOrientation.portraitUp];
  static const List<DeviceOrientation> _landscape = [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  static bool get isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  static bool get isMacOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  /// Avisa quando a janela do macOS entra ou sai da tela cheia por fora do app
  /// (botão verde, Esc, Ctrl+Cmd+F).
  static void listen(void Function(bool fullScreen) onChange) {
    if (!isMacOS) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'fullScreenChanged') onChange(call.arguments == true);
    });
  }

  /// No telefone, como no app do YouTube, a interface fica em pé e só a tela
  /// cheia deita. (Liberar todas as orientações ao sair da tela cheia deixava o
  /// app deitado de novo se o aparelho estivesse deitado.)
  static Future<void> lockPortraitOnPhone({required bool phone}) async {
    if (!isMobile || !phone) return;
    await _try('orientação', () => SystemChrome.setPreferredOrientations(_portrait));
  }

  static Future<void> setFullScreen(bool on, {bool phone = false}) async {
    if (isMobile) {
      // cada passo separado: se um falhar, os outros ainda acontecem
      await _try(
        'barras do sistema',
        () => on
            ? SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)
            : SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values),
      );
      if (phone) {
        await _try('orientação', () => SystemChrome.setPreferredOrientations(on ? _landscape : _portrait));
      }
    } else if (isMacOS) {
      await _try('janela', () => _channel.invokeMethod<void>('setFullScreen', on));
    }
  }

  static Future<void> _try(String what, Future<void> Function() action) async {
    try {
      await action();
    } on PlatformException catch (e) {
      Log.warning('Tela cheia ($what): $e');
    } on MissingPluginException catch (e) {
      Log.warning('Tela cheia ($what): $e');
    }
  }
}
