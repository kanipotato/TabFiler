import AppKit

// 1024x1024のアプリアイコンPNGを描画して書き出す。
// モチーフ: macOS風のsquircle背景 + タブの乗ったフォルダ(タブ式ファイラー)。

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let ctx = NSGraphicsContext.current!.cgContext

func roundedRect(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

// 背景squircle + 青グラデーション
let bgRect = CGRect(x: 0, y: 0, width: size, height: size)
let bgPath = roundedRect(bgRect, radius: size * 0.2237)
bgPath.addClip()
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.30, green: 0.78, blue: 0.47, alpha: 1),
    NSColor(srgbRed: 0.09, green: 0.55, blue: 0.33, alpha: 1)
])!
gradient.draw(in: bgRect, angle: -90)

let white = NSColor(white: 1.0, alpha: 1.0)
let panelGray = NSColor(srgbRed: 0.90, green: 0.92, blue: 0.96, alpha: 1.0)
let tabInactive = NSColor(srgbRed: 0.82, green: 0.88, blue: 0.84, alpha: 1.0)
let accentBlue = NSColor(srgbRed: 0.13, green: 0.66, blue: 0.40, alpha: 1.0)

// ウィンドウ本体（白パネル）
let bodyRect = CGRect(x: 212, y: 230, width: 600, height: 470)
white.setFill()
roundedRect(bodyRect, radius: 60).fill()

// 上部のタブバー帯（薄いグレー）。本体上部に重ねて、角は上だけ丸く見せる。
let barRect = CGRect(x: 212, y: 560, width: 600, height: 140)
panelGray.setFill()
roundedRect(barRect, radius: 60).fill()
white.setFill()
roundedRect(CGRect(x: 212, y: 560, width: 600, height: 70), radius: 0).fill()

// タブ3枚（中央=アクティブを青で強調）。下端を帯の下に潜らせて一体に見せる。
let tabW: CGFloat = 168
let tabH: CGFloat = 150
let tabY: CGFloat = 588
let gap: CGFloat = 18
let totalW = tabW * 3 + gap * 2
var x = bgRect.midX - totalW / 2
for i in 0..<3 {
    let tab = roundedRect(CGRect(x: x, y: tabY, width: tabW, height: tabH), radius: 30)
    (i == 1 ? accentBlue : tabInactive).setFill()
    tab.fill()
    x += tabW + gap
}

// タブと本体の境界を白でならす（タブ下部を本体に溶け込ませる）
white.setFill()
roundedRect(CGRect(x: 212, y: 230, width: 600, height: 372), radius: 60).fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("failed to render\n", stderr)
    exit(1)
}

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
do {
    try png.write(to: URL(fileURLWithPath: outPath))
    print("wrote \(outPath)")
} catch {
    fputs("write error: \(error)\n", stderr)
    exit(1)
}
