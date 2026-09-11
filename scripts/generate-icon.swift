import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 2 else {
    fputs("usage: swift scripts/generate-icon.swift <output.iconset>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: args[1], isDirectory: true)
let fm = FileManager.default
try? fm.removeItem(at: outputURL)
try fm.createDirectory(at: outputURL, withIntermediateDirectories: true)

struct IconVariant {
    let points: Int
    let scale: Int

    var pixels: Int { points * scale }
    var filename: String {
        scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    }
}

let variants: [IconVariant] = [
    .init(points: 16, scale: 1), .init(points: 16, scale: 2),
    .init(points: 32, scale: 1), .init(points: 32, scale: 2),
    .init(points: 128, scale: 1), .init(points: 128, scale: 2),
    .init(points: 256, scale: 1), .init(points: 256, scale: 2),
    .init(points: 512, scale: 1), .init(points: 512, scale: 2),
]

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawIcon(pixelSize: Int) -> NSImage {
    let size = CGFloat(pixelSize)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let context = NSGraphicsContext.current?.cgContext else { return image }
    context.interpolationQuality = .high

    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    context.clear(canvas)

    let inset = size * 0.035
    let tile = canvas.insetBy(dx: inset, dy: inset)
    let radius = size * 0.225
    let tilePath = roundedRect(tile, radius: radius)
    tilePath.addClip()

    let backgroundGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(0x0B1020).cgColor, color(0x172247).cgColor] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        backgroundGradient,
        start: CGPoint(x: tile.minX, y: tile.maxY),
        end: CGPoint(x: tile.maxX, y: tile.minY),
        options: []
    )

    // Soft acoustic glow behind the waveform.
    let glowCenter = CGPoint(x: size * 0.47, y: size * 0.53)
    let glowGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(0x43E7FF, alpha: 0.28).cgColor, color(0x43E7FF, alpha: 0).cgColor] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        glowGradient,
        startCenter: glowCenter,
        startRadius: 0,
        endCenter: glowCenter,
        endRadius: size * 0.55,
        options: []
    )

    // Faint concentric audio rings. They disappear naturally at small sizes.
    if pixelSize >= 64 {
        context.saveGState()
        context.setStrokeColor(color(0x76EFFF, alpha: 0.10).cgColor)
        context.setLineWidth(max(1, size * 0.010))
        for fraction in [0.23, 0.34, 0.45] as [CGFloat] {
            let r = size * fraction
            context.strokeEllipse(in: CGRect(x: glowCenter.x - r, y: glowCenter.y - r, width: r * 2, height: r * 2))
        }
        context.restoreGState()
    }

    // Main waveform: seven rounded bars. Broad silhouettes remain readable at 16 px.
    let centerY = size * 0.52
    let barWidth = max(2, size * 0.075)
    let gap = size * 0.038
    let heights: [CGFloat] = [0.18, 0.34, 0.53, 0.70, 0.48, 0.31, 0.17]
    let totalWidth = barWidth * CGFloat(heights.count) + gap * CGFloat(heights.count - 1)
    let startX = size * 0.5 - totalWidth * 0.5 - size * 0.035

    for (index, heightFactor) in heights.enumerated() {
        let height = max(barWidth, size * heightFactor)
        let x = startX + CGFloat(index) * (barWidth + gap)
        let rect = CGRect(x: x, y: centerY - height * 0.5, width: barWidth, height: height)
        let path = roundedRect(rect, radius: barWidth * 0.5)

        let waveGradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [color(0xF6FDFF).cgColor, color(0x55E6FF).cgColor] as CFArray,
            locations: [0, 1]
        )!
        context.saveGState()
        path.addClip()
        context.drawLinearGradient(
            waveGradient,
            start: CGPoint(x: rect.midX, y: rect.maxY),
            end: CGPoint(x: rect.midX, y: rect.minY),
            options: []
        )
        context.restoreGState()
    }

    // Recording indicator: unmistakable red dot with a subtle outer halo.
    let dotCenter = CGPoint(x: size * 0.765, y: size * 0.265)
    let dotRadius = size * 0.095
    context.setFillColor(color(0xFF5065, alpha: 0.18).cgColor)
    context.fillEllipse(in: CGRect(x: dotCenter.x - dotRadius * 1.42, y: dotCenter.y - dotRadius * 1.42, width: dotRadius * 2.84, height: dotRadius * 2.84))
    context.setFillColor(color(0xFF405A).cgColor)
    context.fillEllipse(in: CGRect(x: dotCenter.x - dotRadius, y: dotCenter.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))

    if pixelSize >= 64 {
        context.setFillColor(NSColor.white.withAlphaComponent(0.28).cgColor)
        let highlightRadius = dotRadius * 0.24
        context.fillEllipse(in: CGRect(x: dotCenter.x - dotRadius * 0.38, y: dotCenter.y + dotRadius * 0.22, width: highlightRadius * 2, height: highlightRadius * 2))
    }

    // Glass-like edge highlight for native macOS icon depth.
    context.saveGState()
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.13).cgColor)
    context.setLineWidth(max(1, size * 0.012))
    context.addPath(CGPath(roundedRect: tile.insetBy(dx: size * 0.012, dy: size * 0.012), cornerWidth: radius * 0.94, cornerHeight: radius * 0.94, transform: nil))
    context.strokePath()
    context.restoreGState()

    return image
}

for variant in variants {
    autoreleasepool {
        let image = drawIcon(pixelSize: variant.pixels)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            fputs("failed to render \(variant.filename)\n", stderr)
            exit(1)
        }
        do {
            try png.write(to: outputURL.appendingPathComponent(variant.filename), options: .atomic)
        } catch {
            fputs("failed to write \(variant.filename): \(error)\n", stderr)
            exit(1)
        }
    }
}

print(outputURL.path)
