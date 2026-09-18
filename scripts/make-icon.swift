#!/usr/bin/env swift

// Renders the app icon from docs/DESIGN.md row 7 into
// Sources/Polish/Resources/Assets.xcassets/AppIcon.appiconset.
// Run: swift scripts/make-icon.swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let plate = CGColor(red: 0xF6 / 255, green: 0xF6 / 255, blue: 0xF4 / 255, alpha: 1)
let ink = CGColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
let accent = CGColor(red: 0, green: 0x7A / 255, blue: 1, alpha: 1)

/// Line runs in the 512-unit design space: (y, x-end, opacity).
let fullLines: [(CGFloat, CGFloat, CGFloat)] = [(232, 200, 0.22), (316, 328, 1), (400, 256, 1)]
let smallLines: [(CGFloat, CGFloat, CGFloat)] = [(320, 328, 1), (404, 244, 1)]

let star: [CGPoint] = [
    CGPoint(x: 348, y: 88), CGPoint(x: 374.5, y: 155.5),
    CGPoint(x: 442, y: 182), CGPoint(x: 374.5, y: 208.5),
    CGPoint(x: 348, y: 276), CGPoint(x: 321.5, y: 208.5),
    CGPoint(x: 254, y: 182), CGPoint(x: 321.5, y: 155.5),
]

func render(px: Int) -> CGImage {
    let ctx = CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // Design space is 512 units with y down; flip and scale to pixels.
    let s = CGFloat(px) / 512
    ctx.translateBy(x: 0, y: CGFloat(px))
    ctx.scaleBy(x: s, y: -s)
    ctx.setAllowsAntialiasing(true)

    ctx.setFillColor(plate)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 512, height: 512),
                       cornerWidth: 115, cornerHeight: 115, transform: nil))
    ctx.fillPath()

    // Below 32 px the faint third line is dropped and strokes thicken.
    let small = px <= 32
    ctx.setLineCap(.round)
    ctx.setLineWidth(small ? 48 : 34)
    for (y, xEnd, opacity) in small ? smallLines : fullLines {
        ctx.setStrokeColor(ink.copy(alpha: opacity)!)
        ctx.move(to: CGPoint(x: 104, y: y))
        ctx.addLine(to: CGPoint(x: xEnd, y: y))
        ctx.strokePath()
    }

    ctx.setFillColor(accent)
    ctx.addLines(between: star)
    ctx.closePath()
    ctx.fillPath()

    return ctx.makeImage()!
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let set = root.appending(path: "Sources/Polish/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)

// macOS app icon: 16/32/128/256/512 pt at 1× and 2×.
let sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var entries: [String] = []
for (pt, scale) in sizes {
    let px = pt * scale
    let name = "icon_\(px).png"
    let url = set.appending(path: name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, render(px: px), nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("failed writing \(name)") }
    entries.append("""
        {
          "filename" : "\(name)",
          "idiom" : "mac",
          "scale" : "\(scale)x",
          "size" : "\(pt)x\(pt)"
        }
    """)
}

let contents = """
{
  "images" : [
\(entries.joined(separator: ",\n"))
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try contents.write(to: set.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
print("wrote \(sizes.count) icon images to \(set.path)")
