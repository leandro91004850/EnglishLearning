import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var windowChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // A janela do app.py: "Legendas YT — PT ⇄ EN", 1280×780, no mínimo 320×200
    // (abaixo de uns 720×460 a interface mostra só o vídeo).
    title = "Legendas YT — PT ⇄ EN"
    minSize = NSSize(width: 320, height: 200)
    backgroundColor = NSColor(red: 0x0f / 255.0, green: 0x0f / 255.0, blue: 0x10 / 255.0, alpha: 1)
    if let visible = (screen ?? NSScreen.main)?.visibleFrame {
      let width = min(1280, visible.width)
      let height = min(780, visible.height)
      setFrame(
        NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height),
        display: true)
    }

    // Tela cheia pedida pelo app (botão de tela cheia, tecla F): lib/src/ui/window_control.dart.
    let channel = FlutterMethodChannel(
      name: "legendas_yt/window", binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let window = self else {
        result(nil)
        return
      }
      switch call.method {
      case "setFullScreen":
        let wanted = (call.arguments as? Bool) ?? false
        if window.styleMask.contains(.fullScreen) != wanted {
          window.toggleFullScreen(nil)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    windowChannel = channel

    // E avisa o app quando a tela cheia muda por fora dele (botão verde, Esc).
    NotificationCenter.default.addObserver(
      forName: NSWindow.didEnterFullScreenNotification, object: self, queue: .main
    ) { [weak self] _ in
      self?.windowChannel?.invokeMethod("fullScreenChanged", arguments: true)
    }
    NotificationCenter.default.addObserver(
      forName: NSWindow.didExitFullScreenNotification, object: self, queue: .main
    ) { [weak self] _ in
      self?.windowChannel?.invokeMethod("fullScreenChanged", arguments: false)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
