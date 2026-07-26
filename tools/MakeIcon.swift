#!/usr/bin/env swift
//
// MakeIcon — draw perch's app icon and emit a full iconset.
//
// Drawn rather than generated so it is exact, reproducible, and correct at every size an icon has
// to survive: 1024px in Finder's preview down to 16px in a list view. A raster generated once at
// one size cannot do that, and a hand-placed bitmap drifts the moment anything changes.
//
// The mark is the notch itself, hanging from the top edge exactly as it hangs from the top of a
// display. A bird was the obvious reading of the name and the wrong one: it could belong to any
// app, it turns to mush below 32px, and floating the notch away from an edge stopped it reading as
// a notch at all. The silhouette alone is unmistakably this app.
//
// Usage:  make icon

import AppKit
import CoreGraphics
import Foundation

// MARK: - Palette

func rgb(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
    CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}

/// A periwinkle gradient, the hue sampled from the wallpaper in the demo recording but pushed
/// richer. The wallpaper's own pastel is lovely at 1024px and dissolves into a light Finder
/// background by 32px, leaving the notch apparently floating on nothing.
let plateTop = rgb(139, 132, 233)
let plateBottom = rgb(88, 84, 176)
let white = CGColor(gray: 1, alpha: 1)

// MARK: - Shapes

/// A macOS-style rounded rectangle.
///
/// Uses a continuous-curvature corner rather than a circular arc: the system's own icons do, and a
/// plain rounded rect next to them reads as subtly wrong — the corner arrives too abruptly.
func squirclePath(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let r = rect.width * 0.2237  // Apple's icon corner radius, as a fraction of the side.
    let c = r * 0.55             // Control-point offset that smooths the arc into the edge.

    path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
    path.addCurve(
        to: CGPoint(x: rect.maxX, y: rect.minY + r),
        control1: CGPoint(x: rect.maxX - c, y: rect.minY),
        control2: CGPoint(x: rect.maxX, y: rect.minY + c))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
    path.addCurve(
        to: CGPoint(x: rect.maxX - r, y: rect.maxY),
        control1: CGPoint(x: rect.maxX, y: rect.maxY - c),
        control2: CGPoint(x: rect.maxX - c, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
    path.addCurve(
        to: CGPoint(x: rect.minX, y: rect.maxY - r),
        control1: CGPoint(x: rect.minX + c, y: rect.maxY),
        control2: CGPoint(x: rect.minX, y: rect.maxY - c))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
    path.addCurve(
        to: CGPoint(x: rect.minX + r, y: rect.minY),
        control1: CGPoint(x: rect.minX, y: rect.minY + c),
        control2: CGPoint(x: rect.minX + c, y: rect.minY))
    path.closeSubpath()
    return path
}

/// The notch silhouette: square where it meets the top, rounded below, concave shoulders.
///
/// The same form perch actually draws on screen, so the icon and the app agree.
/// Coordinates are bottom-left origin, since that is CoreGraphics' convention.
func notchPath(body: CGRect, shoulder: CGFloat, corner: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let top = body.maxY

    path.move(to: CGPoint(x: body.minX - shoulder, y: top))
    path.addQuadCurve(
        to: CGPoint(x: body.minX, y: top - shoulder),
        control: CGPoint(x: body.minX, y: top))
    path.addLine(to: CGPoint(x: body.minX, y: body.minY + corner))
    path.addQuadCurve(
        to: CGPoint(x: body.minX + corner, y: body.minY),
        control: CGPoint(x: body.minX, y: body.minY))
    path.addLine(to: CGPoint(x: body.maxX - corner, y: body.minY))
    path.addQuadCurve(
        to: CGPoint(x: body.maxX, y: body.minY + corner),
        control: CGPoint(x: body.maxX, y: body.minY))
    path.addLine(to: CGPoint(x: body.maxX, y: top - shoulder))
    path.addQuadCurve(
        to: CGPoint(x: body.maxX + shoulder, y: top),
        control: CGPoint(x: body.maxX, y: top))
    path.closeSubpath()
    return path
}

// MARK: - Drawing

func drawIcon(size: CGFloat, markColor: CGColor) -> CGImage? {
    let scale = size / 1024
    guard
        let context = CGContext(
            data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    context.interpolationQuality = .high
    context.setShouldAntialias(true)

    // The plate. Inset slightly, the way system icons leave a margin inside their canvas.
    let plate = CGRect(x: 0, y: 0, width: 1024, height: 1024).insetBy(dx: 52, dy: 52)
    context.scaleBy(x: scale, y: scale)

    context.saveGState()
    context.addPath(squirclePath(in: plate))
    context.clip()

    // A vertical gradient rather than flat colour: it catches light the way a physical object
    // would, and keeps the plate from looking like a flat swatch beside other icons.
    let space = CGColorSpaceCreateDeviceRGB()
    if let gradient = CGGradient(
        colorsSpace: space, colors: [plateTop, plateBottom] as CFArray, locations: [0, 1])
    {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: plate.maxY), end: CGPoint(x: 0, y: plate.minY),
            options: [])
    }
    context.restoreGState()

    // The notch, flush with the top of the plate. Attachment to an edge is what makes the shape
    // read as a notch — floated in the middle it reads as a container, which is what the first
    // attempt looked like.
    let notchWidth = plate.width * 0.58
    let notchBody = CGRect(
        x: plate.midX - notchWidth / 2,
        y: plate.maxY - plate.height * 0.27,
        width: notchWidth,
        height: plate.height * 0.27)
    let notch = notchPath(
        body: notchBody, shoulder: plate.width * 0.05, corner: plate.width * 0.10)

    context.saveGState()
    context.addPath(squirclePath(in: plate))
    context.clip()  // So the shoulders cannot spill past the plate's rounded top corners.
    context.setFillColor(markColor)
    context.addPath(notch)
    context.fillPath()
    context.restoreGState()

    return context.makeImage()
}

// MARK: - Output

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/icon"
/// Near-black, like the hardware. A white notch merges with the transparent area outside the
/// plate and reads as a bite taken out of the icon rather than a notch on a screen.
let markColor = CGColor(gray: 0.07, alpha: 1)
let iconset = URL(fileURLWithPath: output).appendingPathComponent("perch.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

/// The sizes `iconutil` expects, and the names it insists on.
let variants: [(name: String, pixels: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    guard
        let image = drawIcon(size: variant.pixels, markColor: markColor),
        let destination = CGImageDestinationCreateWithURL(
            iconset.appendingPathComponent("\(variant.name).png") as CFURL,
            "public.png" as CFString, 1, nil)
    else {
        print("failed to render \(variant.name)")
        exit(1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

print("wrote \(variants.count) sizes to \(iconset.path)")
