// Gera o ícone do app (quadrado grafite com o SF Symbol "checklist" branco), com a margem transparente
// da grade de ícones do macOS: o quadrado ocupa 824/1024 da tela, centralizado.
//   swift scripts/make-icon.swift /tmp/AppIcon.iconset && iconutil -c icns /tmp/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

let out = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func png(side: Int) -> Data {
    let s = CGFloat(side)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: s, height: s) // 1 ponto = 1 pixel, senão o iconutil recusa o tamanho
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let t = s * 824 / 1024, inset = (s - t) / 2 // lado e margem do quadrado
    let tile = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: t, height: t), xRadius: t * 58 / 256, yRadius: t * 58 / 256)
    tile.addClip()
    NSGradient(starting: NSColor(srgbRed: 0x3D / 255, green: 0x40 / 255, blue: 0x45 / 255, alpha: 1),
               ending: NSColor(srgbRed: 0x1C / 255, green: 0x1C / 255, blue: 0x1F / 255, alpha: 1))!.draw(in: tile, angle: -90)
    // pointSize 104 em 256 dá um símbolo de ~46% do lado do quadrado; escala junto.
    let glyph = NSImage(systemSymbolName: "checklist", accessibilityDescription: nil)!
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: t * 104 / 256, weight: .medium)
            .applying(.init(paletteColors: [.white])))!
    glyph.draw(in: NSRect(x: (s - glyph.size.width) / 2, y: (s - glyph.size.height) / 2,
                          width: glyph.size.width, height: glyph.size.height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try png(side: base * scale).write(to: URL(fileURLWithPath: "\(out)/\(name)"))
    }
}
print("ok")
