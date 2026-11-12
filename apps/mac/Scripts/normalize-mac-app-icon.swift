#!/usr/bin/env swift
import AppKit
import Foundation

let repoRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconDir = repoRoot
    .appendingPathComponent("Kuma/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let masterURL = iconDir.appendingPathComponent("1024.png")

guard let master = NSImage(contentsOf: masterURL) else {
    fputs("Failed to load master icon at \(masterURL.path)\n", stderr)
    exit(1)
}

let px = 1024
let size = NSSize(width: px, height: px)
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: px,
    pixelsHigh: px,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Failed to create bitmap rep\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
    fputs("Failed to create graphics context\n", stderr)
    exit(1)
}
NSGraphicsContext.current = ctx
ctx.imageInterpolation = .high

let rect = NSRect(x: 0, y: 0, width: size.width, height: size.height)
NSColor.clear.set()
rect.fill()

let corner = size.width * 0.2237
let clip = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
clip.addClip()
master.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}
try png.write(to: masterURL)

let exports: [(String, Int)] = [
    ("16.png", 16),
    ("32.png", 32),
    ("32 1.png", 32),
    ("64.png", 64),
    ("128.png", 128),
    ("256.png", 256),
    ("256 1.png", 256),
    ("512.png", 512),
    ("512 1.png", 512),
    ("1024.png", 1024),
]

for (name, dimension) in exports {
    let dest = iconDir.appendingPathComponent(name)
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    proc.arguments = ["-z", "\(dimension)", "\(dimension)", masterURL.path, "--out", dest.path]
    try proc.run()
    proc.waitUntilExit()
    if proc.terminationStatus != 0 {
        fputs("sips failed for \(name)\n", stderr)
        exit(1)
    }
}

print("Normalized AppIcon.appiconset")
