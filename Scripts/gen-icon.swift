import AppKit
import Foundation

// Generates Resources/AppIcon.icns for Inkling — an indigo squircle with a white
// text caret and two faded "ghost text" lines (concept A) — plus two preview PNGs
// in /tmp for inspection. Pure AppKit, no SwiftPM needed.
//   Run from the repo root:  swift Scripts/gen-icon.swift

let indigo = NSColor(srgbRed: 79/255.0, green: 70/255.0, blue: 229/255.0, alpha: 1)

/// The full-color app icon at canvas size S×S (origin bottom-left).
func drawAppIcon(_ S: CGFloat) {
    let margin = S * 0.098, R = S * 0.804
    indigo.setFill()
    NSBezierPath(roundedRect: NSRect(x: margin, y: margin, width: R, height: R),
                 xRadius: R * 0.2247, yRadius: R * 0.2247).fill()
    // ratios are top-down within the squircle; flip Y for AppKit's bottom-left origin
    func rr(_ rx: CGFloat, _ ry: CGFloat, _ rw: CGFloat, _ rh: CGFloat) -> NSRect {
        NSRect(x: margin + rx * R, y: margin + (R - ry * R - rh * R), width: rw * R, height: rh * R)
    }
    NSColor.white.setFill()
    let caret = rr(0.295, 0.259, 0.080, 0.482)
    NSBezierPath(roundedRect: caret, xRadius: caret.width / 2, yRadius: caret.width / 2).fill()
    NSColor(white: 1, alpha: 0.45).setFill()
    for g in [rr(0.455, 0.366, 0.321, 0.098), rr(0.455, 0.536, 0.232, 0.098)] {
        NSBezierPath(roundedRect: g, xRadius: g.height / 2, yRadius: g.height / 2).fill()
    }
}

/// The menu-bar glyph (caret + single suggestion line) drawn in `color`, fit to rect.
func drawMenuGlyph(_ rect: NSRect, _ color: NSColor) {
    color.setFill()
    let S = rect.height, W = rect.width
    let cw = S * 0.12, ch = S * 0.80
    let caret = NSRect(x: rect.minX + W * 0.28 - cw / 2, y: rect.minY + (S - ch) / 2, width: cw, height: ch)
    NSBezierPath(roundedRect: caret, xRadius: cw / 2, yRadius: cw / 2).fill()
    let lh = S * 0.16, lw = W * 0.42
    let line = NSRect(x: rect.minX + W * 0.42, y: rect.minY + (S - lh) / 2, width: lw, height: lh)
    NSBezierPath(roundedRect: line, xRadius: lh / 2, yRadius: lh / 2).fill()
}

func pngRep(_ w: Int, _ h: Int, _ draw: () -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let root = fm.currentDirectoryPath
let iconset = "\(root)/Resources/AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    let data = pngRep(px, px) { drawAppIcon(CGFloat(px)) }
    try! data.write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
}

let icon = Process()
icon.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
icon.arguments = ["-c", "icns", iconset, "-o", "\(root)/Resources/AppIcon.icns"]
try! icon.run(); icon.waitUntilExit()
try? fm.removeItem(atPath: iconset)   // keep only the .icns

// Previews for inspection.
try! pngRep(256, 256) { drawAppIcon(256) }
    .write(to: URL(fileURLWithPath: "/tmp/inkling-appicon.png"))
try! pngRep(260, 92) {
    NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 260, height: 92), xRadius: 16, yRadius: 16).fill()
    drawMenuGlyph(NSRect(x: 95, y: 29, width: 70, height: 34), .white)
}.write(to: URL(fileURLWithPath: "/tmp/inkling-menubar.png"))

print("OK: wrote Resources/AppIcon.icns (iconutil exit \(icon.terminationStatus)) + /tmp previews")
