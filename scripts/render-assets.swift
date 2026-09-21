// Rebuild the original vector artwork with: swift scripts/render-assets.swift
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources")
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
}
let lavender = color(0.73, 0.67, 1)

func png(width: Int, height: Int, at url: URL, draw: () -> Void) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

func icon(size: Int, at url: URL) throws {
    try png(width: size, height: size, at: url) {
        NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        let tile = NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 192, yRadius: 192)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 26
        shadow.shadowOffset = NSSize(width: 0, height: -14)
        shadow.set()
        color(0.12, 0.11, 0.19).setFill()
        tile.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: color(0.23, 0.20, 0.34), ending: color(0.09, 0.09, 0.14))!.draw(in: tile, angle: -90)
        color(0.42, 0.37, 0.55).withAlphaComponent(0.7).setStroke()
        tile.lineWidth = 3
        tile.stroke()

        let screen = NSBezierPath(roundedRect: NSRect(x: 197, y: 243, width: 630, height: 537), xRadius: 62, yRadius: 62)
        color(0.08, 0.08, 0.12).setFill()
        screen.fill()
        lavender.withAlphaComponent(0.85).setStroke()
        screen.lineWidth = 15
        screen.stroke()
        lavender.withAlphaComponent(0.25).setFill()
        NSRect(x: 205, y: 654, width: 614, height: 3).fill()
        for x in [255, 299, 343] {
            lavender.withAlphaComponent(x == 255 ? 0.95 : 0.35).setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: 696, width: 19, height: 19)).fill()
        }
        lavender.setStroke()
        let prompt = NSBezierPath()
        prompt.move(to: NSPoint(x: 293, y: 559))
        prompt.line(to: NSPoint(x: 390, y: 474))
        prompt.line(to: NSPoint(x: 293, y: 389))
        prompt.lineWidth = 43
        prompt.lineCapStyle = .round
        prompt.lineJoinStyle = .round
        prompt.stroke()
        let cursor = NSBezierPath()
        cursor.move(to: NSPoint(x: 481, y: 394))
        cursor.line(to: NSPoint(x: 572, y: 394))
        cursor.lineWidth = 40
        cursor.lineCapStyle = .round
        cursor.stroke()
        // A small usage meter gives the terminal mark its own identity.
        for (index, height) in [58, 102, 153].enumerated() {
            lavender.withAlphaComponent(CGFloat(index + 2) / 4).setFill()
            NSBezierPath(roundedRect: NSRect(x: 647 + index * 40, y: 376, width: 23, height: height), xRadius: 6, yRadius: 6).fill()
        }
    }
}

for size in [16, 32, 128, 256, 512] {
    try icon(size: size, at: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try icon(size: size * 2, at: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try icon(size: 1024, at: resources.appendingPathComponent("AppIcon.png"))

try png(width: 660, height: 420, at: resources.appendingPathComponent("DMGBackground.png")) {
    color(0.965, 0.957, 0.984).setFill()
    NSRect(x: 0, y: 0, width: 660, height: 420).fill()
    color(0.49, 0.39, 0.74).setFill()
    NSRect(x: 0, y: 416, width: 660, height: 4).fill()
    func text(_ value: String, top: CGFloat, size: CGFloat, weight: NSFont.Weight, ink: NSColor) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        (value as NSString).draw(in: NSRect(x: 20, y: 420 - top - size * 1.5, width: 620, height: size * 1.5),
            withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: ink, .paragraphStyle: style])
    }
    text("Codex Widget", top: 39, size: 30, weight: .semibold, ink: color(0.17, 0.14, 0.24))
    text("Drag to Applications to install", top: 87, size: 15, weight: .regular, ink: color(0.41, 0.37, 0.49))
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 294, y: 200))
    arrow.line(to: NSPoint(x: 363, y: 200))
    arrow.move(to: NSPoint(x: 349, y: 214))
    arrow.line(to: NSPoint(x: 364, y: 200))
    arrow.line(to: NSPoint(x: 349, y: 186))
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    color(0.56, 0.47, 0.71).setStroke()
    arrow.stroke()
    text("Then open it from Applications.", top: 342, size: 13, weight: .medium, ink: color(0.33, 0.29, 0.42))
    text("Look for the terminal icon in your menu bar.", top: 367, size: 12, weight: .regular, ink: color(0.47, 0.42, 0.53))
}
