#!/usr/bin/env swift
import AppKit
import Foundation

// Renders AppIcon.icns from code — no design tool, no binary asset to keep in sync with
// the HUD palette. Run: swift Tools/makeicon.swift

// Matches `Brand` in HUDView.swift. Change both together.
let accent = NSColor(srgbRed: 0.42, green: 0.55, blue: 1.00, alpha: 1)
let accentWarm = NSColor(srgbRed: 0.76, green: 0.47, blue: 1.00, alpha: 1)

/// Relative bar heights, center-weighted so the mark reads as a voice waveform rather
/// than a bar chart.
let bars: [CGFloat] = [0.30, 0.52, 0.78, 1.00, 0.82, 0.56, 0.34]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // macOS Big Sur+ icon grid: art occupies the middle ~82%, leaving the shadow gutter
    // the system expects.
    let inset = size * 0.09
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    // Apple's squircle is ~22.37% of the tile's edge.
    let radius = rect.width * 0.2237

    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.012),
        blur: size * 0.035,
        color: NSColor.black.withAlphaComponent(0.30).cgColor
    )
    ctx.addPath(squircle)
    ctx.setFillColor(accent.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Diagonal brand gradient.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [accent.cgColor, accentWarm.cgColor] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )

    // Soft top highlight so the tile reads as glass rather than flat fill.
    let highlight = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor.white.withAlphaComponent(0.28).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor,
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        highlight,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.midY),
        options: []
    )
    ctx.restoreGState()

    // Waveform mark.
    let barWidth = rect.width * 0.072
    let gap = rect.width * 0.050
    let totalWidth = CGFloat(bars.count) * barWidth + CGFloat(bars.count - 1) * gap
    let maxHeight = rect.height * 0.46
    var x = rect.midX - totalWidth / 2

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.004),
        blur: size * 0.014,
        color: NSColor.black.withAlphaComponent(0.22).cgColor
    )
    ctx.setFillColor(NSColor.white.cgColor)
    for bar in bars {
        let height = max(barWidth, maxHeight * bar)
        let barRect = CGRect(x: x, y: rect.midY - height / 2, width: barWidth, height: height)
        ctx.addPath(CGPath(
            roundedRect: barRect,
            cornerWidth: barWidth / 2,
            cornerHeight: barWidth / 2,
            transform: nil
        ))
        ctx.fillPath()
        x += barWidth + gap
    }
    ctx.restoreGState()

    image.unlockFocus()
    return image
}

func png(_ image: NSImage, pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // Redraw at native pixel size rather than scaling a single render — keeps the small
    // sizes crisp instead of muddy.
    drawIcon(size: CGFloat(pixels)).draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: .zero, operation: .sourceOver, fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root.appendingPathComponent("Resources/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

// (point size, scale) pairs iconutil expects.
let variants: [(Int, Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
    (256, 1), (256, 2), (512, 1), (512, 2),
]

for (points, scale) in variants {
    let pixels = points * scale
    guard let data = png(NSImage(), pixels: pixels) else {
        print("failed at \(pixels)px"); exit(1)
    }
    let suffix = scale == 2 ? "@2x" : ""
    let name = "icon_\(points)x\(points)\(suffix).png"
    try data.write(to: iconset.appendingPathComponent(name))
}

print("wrote \(variants.count) PNGs to Resources/AppIcon.iconset")
