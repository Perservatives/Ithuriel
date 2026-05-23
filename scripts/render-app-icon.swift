#!/usr/bin/env swift
import AppKit
import SwiftUI

private struct Petal: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let h = rect.height
        let cx = rect.midX
        p.move(to: CGPoint(x: cx, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: cx, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.midY + h * 0.05)
        )
        p.addQuadCurve(
            to: CGPoint(x: cx, y: rect.minY),
            control: CGPoint(x: rect.maxX, y: rect.midY + h * 0.05)
        )
        p.closeSubpath()
        return p
    }
}

private struct AppIconMark: View {
    let size: CGFloat

    var body: some View {
        let petalLen = size * 0.46
        let petalWid = size * 0.18
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                Petal()
                    .fill(i.isMultiple(of: 2) ? Color.white : Color.white.opacity(0.62))
                    .frame(width: petalWid, height: petalLen)
                    .offset(y: -petalLen / 2)
                    .rotationEffect(.degrees(Double(i) * 45))
            }
        }
        .frame(width: size, height: size)
    }
}

private struct AppIconCanvas: View {
    var body: some View {
        ZStack {
            Color(red: 0.11, green: 0.11, blue: 0.12)
            AppIconMark(size: 520)
        }
        .frame(width: 1024, height: 1024)
    }
}

private func renderMasterPNG(to url: URL) throws {
    let size = 1024
    let side = CGFloat(size)
    let hosting = NSHostingView(rootView: AppIconCanvas().frame(width: side, height: side))
    hosting.frame = NSRect(x: 0, y: 0, width: side, height: side)
    hosting.layoutSubtreeIfNeeded()

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "render-app-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "NSBitmapImageRep init failed"])
    }
    rep.size = NSSize(width: side, height: side)

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "render-app-icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "NSGraphicsContext init failed"])
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    hosting.layer?.render(in: ctx.cgContext)
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "render-app-icon", code: 3, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
    }
    try png.write(to: url)
}

private func resizePNG(from source: URL, to destination: URL, size: Int) throws {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    task.arguments = ["-z", String(size), String(size), source.path, "--out", destination.path]
    try task.run()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else {
        throw NSError(domain: "render-app-icon", code: 4, userInfo: [NSLocalizedDescriptionKey: "sips resize failed for \(destination.lastPathComponent)"])
    }
}

do {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let appIconDir = root.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
        try FileManager.default.createDirectory(at: appIconDir, withIntermediateDirectories: true)

        let mappings: [(name: String, size: Int)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024)
        ]

        let master = appIconDir.appendingPathComponent("master_1024.png")
        try renderMasterPNG(to: master)

        for mapping in mappings {
            let url = appIconDir.appendingPathComponent(mapping.name)
            try resizePNG(from: master, to: url, size: mapping.size)
            print("Wrote \(mapping.name)")
        }
        try FileManager.default.removeItem(at: master)

        let contents = """
        {
          "images" : [
            { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
            { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
            { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
            { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
            { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
            { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
            { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
            { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
            { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
            { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
          ],
          "info" : { "author" : "xcode", "version" : 1 }
        }
        """
        try contents.write(to: appIconDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

        let catalog = """
        {
          "info" : { "author" : "xcode", "version" : 1 }
        }
        """
        try catalog.write(to: root.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

    print("App icon set written to \(appIconDir.path)")
} catch {
    fputs("render-app-icon failed: \(error)\n", stderr)
    exit(1)
}
