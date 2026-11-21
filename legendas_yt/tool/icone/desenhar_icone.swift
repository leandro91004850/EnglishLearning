// Desenha o ícone do Legendas YT e grava as imagens-mestre numa pasta. Quem roda é o
// tool/icone/gerar.sh, que tira delas todos os tamanhos de cada plataforma:
//
//   sh tool/icone/gerar.sh
//
// O desenho: uma tela de vídeo coral em forma de balão de fala (vídeo + idioma),
// com o botão de play e, embaixo, a legenda dupla do app: uma linha branca
// (fala original) e uma amarela (tradução) sobre a faixa escura. Fundo azul-noite.
// Coordenadas num quadrado de 1024, origem no canto de cima à esquerda.
import AppKit
import CoreGraphics

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
  CGColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
    green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255,
    alpha: alpha)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
  CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locations)!
}

/// Contexto com a origem no canto de cima à esquerda (como no desenho).
func canvas(_ size: Int, opaque: Bool) -> CGContext {
  let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
  let c = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: sRGB, bitmapInfo: info)!
  c.interpolationQuality = .high
  c.setAllowsAntialiasing(true)
  c.translateBy(x: 0, y: CGFloat(size))
  c.scaleBy(x: 1, y: -1)
  return c
}

func save(_ c: CGContext, _ path: String) {
  let rep = NSBitmapImageRep(cgImage: c.makeImage()!)
  try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
  print("gravado \(path)")
}

// ---- partes do desenho -------------------------------------------------------

let navyTop: UInt32 = 0x2C3690
let navyBottom: UInt32 = 0x0C1033
let coralTop: UInt32 = 0xFF7B68
let coralBottom: UInt32 = 0xEC4034
let plate: UInt32 = 0x0F1338
let white: UInt32 = 0xFFFFFF
let yellow: UInt32 = 0xFFD866

func background(_ c: CGContext) {
  c.drawLinearGradient(
    gradient([rgb(navyTop), rgb(navyBottom)]),
    start: CGPoint(x: 120, y: 0), end: CGPoint(x: 904, y: 1024), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
  // brilho coral atrás do balão
  c.drawRadialGradient(
    gradient([rgb(0xFF6A55, 0.32), rgb(0xFF6A55, 0)]),
    startCenter: CGPoint(x: 512, y: 440), startRadius: 0,
    endCenter: CGPoint(x: 512, y: 440), endRadius: 560, options: [])
}

/// O balão: a tela de vídeo e a ponta embaixo, à esquerda (duas formas, pintadas
/// uma de cada vez, para a parte em comum não se anular).
let screenRect = CGRect(x: 152, y: 176, width: 720, height: 500)

func screenPath() -> CGPath {
  CGPath(roundedRect: screenRect, cornerWidth: 118, cornerHeight: 118, transform: nil)
}

func tailPath() -> CGPath {
  // a base fica dentro da tela, abaixo da faixa da legenda, e a ponta sai por baixo
  let tail = CGMutablePath()
  tail.move(to: CGPoint(x: 268, y: 648))
  tail.addLine(to: CGPoint(x: 238, y: 792))
  tail.addQuadCurve(to: CGPoint(x: 424, y: 662), control: CGPoint(x: 300, y: 748))
  tail.closeSubpath()
  return tail
}

func roundedBar(_ c: CGContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, color: CGColor) {
  c.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: h / 2, cornerHeight: h / 2, transform: nil))
  c.setFillColor(color)
  c.fillPath()
}

/// Uma linha de "palavras" centralizada.
func textLine(_ c: CGContext, y: CGFloat, h: CGFloat, words: [CGFloat], gap: CGFloat, color: CGColor) {
  let total = words.reduce(0, +) + gap * CGFloat(words.count - 1)
  var x = 512 - total / 2
  for w in words {
    roundedBar(c, x: x, y: y, w: w, h: h, color: color)
    x += w + gap
  }
}

/// O desenho num quadrado de 1024 (o contexto já escalado). [scale] só serve para
/// a sombra, que não acompanha a escala do contexto.
func art(_ c: CGContext, scale: CGFloat, withBackground: Bool) {
  if withBackground { background(c) }

  // balão coral com sombra macia
  c.saveGState()
  c.setShadow(offset: CGSize(width: 0, height: -22 * scale), blur: 46 * scale, color: rgb(0x000000, 0.45))
  c.beginTransparencyLayer(auxiliaryInfo: nil)
  let coral = gradient([rgb(coralTop), rgb(coralBottom)])
  for shape in [screenPath(), tailPath()] {
    c.saveGState()
    c.addPath(shape)
    c.clip()
    c.drawLinearGradient(coral, start: CGPoint(x: 0, y: 176), end: CGPoint(x: 0, y: 792), options: [])
    c.restoreGState()
  }
  // reflexo de luz no alto da tela
  c.saveGState()
  c.addPath(screenPath())
  c.clip()
  c.drawLinearGradient(
    gradient([rgb(white, 0.20), rgb(white, 0)]),
    start: CGPoint(x: 0, y: 176), end: CGPoint(x: 0, y: 380), options: [])
  c.restoreGState()
  c.endTransparencyLayer()
  c.restoreGState()

  // play, com as pontas arredondadas (a sombra vale para a forma inteira)
  let play = CGMutablePath()
  play.move(to: CGPoint(x: 466, y: 248))
  play.addLine(to: CGPoint(x: 466, y: 404))
  play.addLine(to: CGPoint(x: 600, y: 326))
  play.closeSubpath()
  c.saveGState()
  c.setShadow(offset: CGSize(width: 0, height: -6 * scale), blur: 14 * scale, color: rgb(0x8A1F18, 0.35))
  c.beginTransparencyLayer(auxiliaryInfo: nil)
  c.addPath(play)
  c.setFillColor(rgb(white))
  c.setStrokeColor(rgb(white))
  c.setLineWidth(40)
  c.setLineJoin(.round)
  c.drawPath(using: .fillStroke)
  c.endTransparencyLayer()
  c.restoreGState()

  // faixa da legenda, com a linha original (branca) e a tradução (amarela)
  c.addPath(CGPath(roundedRect: CGRect(x: 206, y: 462, width: 612, height: 176), cornerWidth: 48, cornerHeight: 48, transform: nil))
  c.setFillColor(rgb(plate, 0.88))
  c.fillPath()
  textLine(c, y: 496, h: 42, words: [150, 118, 182], gap: 24, color: rgb(white))
  textLine(c, y: 564, h: 42, words: [204, 170], gap: 24, color: rgb(yellow))
}

/// Desenha no quadrado [rect] do contexto como se ele fosse o quadrado de 1024 do
/// desenho; o bloco recebe a escala.
func within(_ c: CGContext, _ rect: CGRect, _ draw: (CGFloat) -> Void) {
  c.saveGState()
  c.translateBy(x: rect.minX, y: rect.minY)
  let s = rect.width / 1024
  c.scaleBy(x: s, y: s)
  draw(s)
  c.restoreGState()
}

/// Desenha [art] dentro do quadrado [rect] do contexto.
func drawArt(_ c: CGContext, in rect: CGRect, withBackground: Bool) {
  within(c, rect) { s in art(c, scale: s, withBackground: withBackground) }
}

// ---- as imagens ---------------------------------------------------------------

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

// iOS: quadrado cheio, sem transparência (o iOS arredonda os cantos)
do {
  let c = canvas(1024, opaque: true)
  drawArt(c, in: CGRect(x: 0, y: 0, width: 1024, height: 1024), withBackground: true)
  save(c, "\(out)/ios_1024.png")
}

// macOS: o "quadrado arredondado" com margem e sombra, como os ícones do macOS
do {
  let c = canvas(1024, opaque: false)
  let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
  let shape = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
  c.saveGState()
  c.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.38))
  c.addPath(shape)
  c.setFillColor(rgb(navyBottom))
  c.fillPath()
  c.restoreGState()
  c.saveGState()
  c.addPath(shape)
  c.clip()
  drawArt(c, in: tile, withBackground: true)
  c.restoreGState()
  save(c, "\(out)/macos_1024.png")
}

// Android, ícone adaptativo (8.0+): duas camadas de 108 dp, o fundo e o desenho por
// cima. O desenho fica dentro da zona segura (o círculo de 66 dp no meio) e o brilho
// do fundo, atrás dele.
do {
  let a: CGFloat = 300
  let rect = CGRect(x: (432 - a) / 2, y: (432 - a) / 2 - 6, width: a, height: a)
  let front = canvas(432, opaque: false)
  drawArt(front, in: rect, withBackground: false)
  save(front, "\(out)/android_foreground_432.png")
  let back = canvas(432, opaque: true)
  within(back, rect) { _ in background(back) }
  save(back, "\(out)/android_background_432.png")
}

// Android antigo: o quadrado arredondado inteiro
do {
  let c = canvas(1024, opaque: false)
  let tile = CGRect(x: 48, y: 48, width: 928, height: 928)
  c.addPath(CGPath(roundedRect: tile, cornerWidth: 200, cornerHeight: 200, transform: nil))
  c.clip()
  drawArt(c, in: tile, withBackground: true)
  save(c, "\(out)/android_legacy_1024.png")
}
