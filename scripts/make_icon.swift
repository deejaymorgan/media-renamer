#!/usr/bin/env swift
//
// make_icon.swift — generate a PLACEHOLDER app icon for MediaRenamer.
//
// Renders a clean SF-Symbols-style film mark on an indigo→blue squircle into
// the AppIcon.appiconset at every size macOS needs. No external dependencies —
// uses AppKit/CoreGraphics from the system toolchain only.
//
//   swift scripts/make_icon.swift            # writes into the default iconset
//   swift scripts/make_icon.swift <iconset>  # or an explicit .appiconset dir
//
// This is intentionally a placeholder; replace with final art.
//
import AppKit

let defaultIconset =
    "MediaRenamer/MediaRenamer/Assets.xcassets/AppIcon.appiconset"
let iconsetDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : defaultIconset

// Unique pixel sizes referenced by the 16/32/128/256/512 @1x+@2x slots.
let pixelSizes = [16, 32, 64, 128, 256, 512, 1024]

let symbolName = "film.fill"
let topColor = NSColor(srgbRed: 0.36, green: 0.36, blue: 0.92, alpha: 1)   // indigo
let bottomColor = NSColor(srgbRed: 0.18, green: 0.55, blue: 0.93, alpha: 1) // blue

func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
    let out = NSImage(size: image.size)
    out.lockFocus()
    color.set()
    let rect = NSRect(origin: .zero, size: image.size)
    image.draw(in: rect)
    rect.fill(using: .sourceAtop)
    out.unlockFocus()
    return out
}

func makeIcon(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    let cg = gctx.cgContext
    let p = CGFloat(pixels)

    // Squircle background with a vertical gradient (macOS-style margin).
    let margin = p * 0.10
    let side = p - 2 * margin
    let rect = CGRect(x: margin, y: margin, width: side, height: side)
    let radius = side * 0.2237
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius,
                      transform: nil)
    cg.saveGState()
    cg.addPath(path)
    cg.clip()
    let grad = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [topColor.cgColor, bottomColor.cgColor] as CFArray,
        locations: [0, 1])!
    cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: p), end: CGPoint(x: 0, y: 0),
                          options: [])
    cg.restoreGState()

    // White film glyph, centred, ~52% of the canvas, aspect-preserved.
    let config = NSImage.SymbolConfiguration(pointSize: p, weight: .semibold)
    guard let raw = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else {
        fatalError("SF Symbol \(symbolName) unavailable")
    }
    let glyph = tinted(raw, .white)
    let box = p * 0.52
    let aspect = glyph.size.width / max(glyph.size.height, 1)
    var w = box, h = box
    if aspect >= 1 { h = box / aspect } else { w = box * aspect }
    glyph.draw(in: CGRect(x: (p - w) / 2, y: (p - h) / 2, width: w, height: h))

    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encode failed")
    }
    return data
}

let fm = FileManager.default
for px in pixelSizes {
    let data = makeIcon(pixels: px)
    let url = URL(fileURLWithPath: iconsetDir).appendingPathComponent("icon_\(px).png")
    do {
        try data.write(to: url)
        print("wrote \(url.lastPathComponent) (\(data.count) bytes)")
    } catch {
        FileHandle.standardError.write(Data("failed \(url.path): \(error)\n".utf8))
        exit(1)
    }
}
print("done — \(pixelSizes.count) PNGs into \(iconsetDir)")
