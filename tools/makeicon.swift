//  Copyright (C) 2026 qarge
//  SPDX-License-Identifier: GPL-3.0-or-later

// Draws Resources/AppIcon.icns. Run with: make icon
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns"
let iconset = NSTemporaryDirectory() + "HoldOn.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func png(_ size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let plate = NSRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.055, dy: s * 0.055)
    let path = NSBezierPath(roundedRect: plate, xRadius: s * 0.225, yRadius: s * 0.225)
    NSGradient(colors: [NSColor(srgbRed: 0.40, green: 0.32, blue: 0.92, alpha: 1),
                        NSColor(srgbRed: 0.21, green: 0.16, blue: 0.55, alpha: 1)])!.draw(in: path, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: s * 0.46, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        // Tint on a transparent layer: .sourceAtop over the opaque plate would paint the whole box.
        let white = NSImage(size: symbol.size)
        white.lockFocus()
        symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        NSColor.white.set()
        NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
        white.unlockFocus()
        white.draw(in: NSRect(x: (s - symbol.size.width) / 2, y: (s - symbol.size.height) / 2,
                              width: symbol.size.width, height: symbol.size.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (size, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"),
                     (128, "128x128"), (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"),
                     (512, "512x512"), (1024, "512x512@2x")] {
    try! png(size).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset, "-o", out]
try! iconutil.run()
iconutil.waitUntilExit()
print("wrote \(out)")
