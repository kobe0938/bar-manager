// Renders the app icon (a chevron on a dark rounded square) to icon.icns. Run with: swift make-icon.swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let iconset = root.appendingPathComponent("build/icon.iconset")
let icns = root.appendingPathComponent("icon.icns")

func render(size: Int) -> NSImage {
    let side = CGFloat(size)
    return NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
        let square = NSRect(x: 0, y: 0, width: side, height: side).insetBy(dx: side * 0.08, dy: side * 0.08)
        NSColor(white: 0.12, alpha: 1).setFill()
        NSBezierPath(roundedRect: square, xRadius: square.width * 0.22, yRadius: square.width * 0.22).fill()

        let chevron = NSBezierPath()
        chevron.lineWidth = side * 0.09
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        let tipX = square.midX - side * 0.1
        chevron.move(to: NSPoint(x: tipX + side * 0.2, y: square.midY + side * 0.24))
        chevron.line(to: NSPoint(x: tipX, y: square.midY))
        chevron.line(to: NSPoint(x: tipX + side * 0.2, y: square.midY - side * 0.24))
        NSColor.white.setStroke()
        chevron.stroke()
        return true
    }
}

func writePNG(_ image: NSImage, size: Int, to url: URL) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    writePNG(render(size: base), size: base, to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(render(size: base * 2), size: base * 2, to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", "--output", icns.path, iconset.path]
try! iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("wrote \(icns.path)")
