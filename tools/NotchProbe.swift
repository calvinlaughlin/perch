#!/usr/bin/env swift
//
// NotchProbe — verify what perch actually draws against what the hardware actually is.
//
// Unit tests can prove NotchMetrics computes the right numbers. They cannot prove those numbers
// survive AppKit and SwiftUI: window origins get rounded to whole points, hosting views apply
// safe-area insets, oversized children interact with alignment and clipping in ways that shift
// and truncate the result. Every one of those failed silently during this project, each producing
// visibly wrong pixels while every test stayed green.
//
// So this measures the screen. It launches perch itself, captures a clean baseline first, and
// diffs — which means it does not care what is behind the notch or what colour perch draws in.
//
// It checks BOTH states. An earlier version checked only the collapsed one and happily passed
// while the expanded panel was clipped by eight points on one side.
//
// Usage:  make probe          (builds, runs this, cleans up)
//         swift tools/NotchProbe.swift path/to/perch
//
// Exits non-zero on any deviation beyond half a backing pixel.

import AppKit
import CoreGraphics
import Foundation

// MARK: - Hardware

guard
    let screen = NSScreen.screens.first(where: {
        $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil
            && $0.auxiliaryTopRightArea != nil
    })
else {
    print("no display with a camera housing — nothing to probe")
    exit(0)
}

let scale = screen.backingScaleFactor
let housingLeft = screen.frame.minX + (screen.auxiliaryTopLeftArea?.width ?? 0)
let housingRight = screen.frame.maxX - (screen.auxiliaryTopRightArea?.width ?? 0)
let housingCentre = (housingLeft + housingRight) / 2
let housingHeight = screen.safeAreaInsets.top
let tolerance = 1.0 / scale  // one backing pixel, to absorb edge antialiasing

let binary =
    CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "build/perch.app/Contents/MacOS/perch"

// Sample only the band beside and behind the notch. It is menu bar and wallpaper — content that
// does not repaint between captures. Sampling further down would race against app windows and
// produce diffs that have nothing to do with perch.
// The capture origin must be a whole point. `screencapture -R` floors fractional coordinates, so
// a fractional origin here silently offsets every measurement by half a point — which reads as a
// half-point drift in perch and sends you hunting for a bug that is in the ruler, not the thing
// being measured. That happened. Round it.
let captureWidth = min(700.0, screen.frame.width).rounded(.down)
let captureX = max(screen.frame.minX, housingCentre - captureWidth / 2).rounded(.down)
let captureHeight = housingHeight.rounded(.up)

// MARK: - Pointer

/// Park the pointer somewhere harmless, or put it on the notch to force the panel open.
func movePointer(to point: CGPoint) {
    CGWarpMouseCursorPosition(point)
    CGEvent(
        mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point,
        mouseButton: .left
    )?.post(tap: .cghidEventTap)
}

let parkingSpot = CGPoint(x: screen.frame.midX, y: screen.frame.maxY - 200)
let onTheNotch = CGPoint(x: housingCentre, y: housingHeight / 2)

// MARK: - Capture

func capture(label: String) -> [UInt8]? {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("perch-probe-\(label)-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: url) }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    // `-x` is silent and, importantly, excludes the cursor — so moving the pointer between
    // captures cannot itself show up as a difference.
    task.arguments = ["-x", "-R\(captureX),0,\(captureWidth),\(captureHeight)", url.path]
    guard (try? task.run()) != nil else { return nil }
    task.waitUntilExit()

    guard
        task.terminationStatus == 0,
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }

    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    guard
        let context = CGContext(
            data: &pixels, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

    pixelWidth = image.width
    pixelHeight = image.height
    return pixels
}

var pixelWidth = 0
var pixelHeight = 0

/// The horizontal extent perch painted on a given row, in points, or nil if it painted nothing.
func drawnSpan(row: Int, _ before: [UInt8], _ after: [UInt8]) -> (left: CGFloat, right: CGFloat)? {
    var first = -1
    var last = -1
    for x in 0..<pixelWidth {
        let i = (row * pixelWidth + x) * 4
        let delta =
            abs(Int(before[i]) - Int(after[i]))
            + abs(Int(before[i + 1]) - Int(after[i + 1]))
            + abs(Int(before[i + 2]) - Int(after[i + 2]))
        if delta > 28 {
            if first < 0 { first = x }
            last = x
        }
    }
    guard first >= 0 else { return nil }
    return (captureX + CGFloat(first) / scale, captureX + CGFloat(last + 1) / scale)
}

// MARK: - Run

_ = try? Process.run(URL(fileURLWithPath: "/usr/bin/pkill"), arguments: ["-x", "perch"])
Thread.sleep(forTimeInterval: 0.6)

movePointer(to: parkingSpot)
Thread.sleep(forTimeInterval: 0.4)

guard let baseline = capture(label: "baseline") else {
    print("screen capture failed — grant Screen Recording permission to your terminal")
    exit(2)
}

let perch = Process()
perch.executableURL = URL(fileURLWithPath: binary)
perch.standardOutput = FileHandle.nullDevice
perch.standardError = FileHandle.nullDevice
do { try perch.run() } catch {
    print("could not launch \(binary): \(error)")
    exit(2)
}
defer {
    perch.terminate()
    movePointer(to: parkingSpot)
}
Thread.sleep(forTimeInterval: 2.0)

var failures: [String] = []

// MARK: - Collapsed
//
// The invariant is one-sided on purpose. A row narrower than the housing is invisible — the camera
// housing is opaque, so anything inside it is hidden, which is what the shape's bottom corner
// rounding looks like from out here. A row *wider* than the housing lands on the menu bar, where
// the user sees it.

guard let collapsed = capture(label: "collapsed") else {
    print("capture failed")
    exit(2)
}

print("housing: \(housingLeft) .. \(housingRight) pt (centre \(housingCentre)), \(housingHeight)pt tall @\(scale)x")
print("tolerance: \(tolerance)pt\n")
print("COLLAPSED")

var collapsedOverruns = 0
for row in 0..<pixelHeight {
    guard let span = drawnSpan(row: row, baseline, collapsed) else { continue }
    if span.left < housingLeft - tolerance || span.right > housingRight + tolerance {
        collapsedOverruns += 1
    }
    if row == 0 {
        print(String(format: "  top row: %.1f .. %.1f", span.left, span.right))
        if abs(span.left - housingLeft) > tolerance || abs(span.right - housingRight) > tolerance {
            failures.append(
                String(
                    format: "collapsed top row spans %.1f..%.1f, housing is %.1f..%.1f",
                    span.left, span.right, housingLeft, housingRight))
        }
    }
}
if collapsedOverruns > 0 {
    failures.append("collapsed shape spills onto the menu bar on \(collapsedOverruns) row(s)")
}
print("  rows spilling past the housing: \(collapsedOverruns)")

// MARK: - Expanded
//
// Checked for symmetry about the housing centre rather than against an absolute width, so the
// probe stays correct whatever `expanded-width` is set to. Asymmetry is exactly what a clipped or
// shifted panel produces, and it is what the eye actually notices.

movePointer(to: onTheNotch)
Thread.sleep(forTimeInterval: 1.5)

guard let expanded = capture(label: "expanded") else {
    print("capture failed")
    exit(2)
}

print("\nEXPANDED")

var asymmetric = 0
var sampled = 0
var topSpan: (left: CGFloat, right: CGFloat)?
var bodySpan: (left: CGFloat, right: CGFloat)?

for row in 0..<pixelHeight {
    guard let span = drawnSpan(row: row, baseline, expanded) else { continue }
    sampled += 1
    if row == 0 { topSpan = span }
    // Below the shoulders the width settles to the panel body.
    if CGFloat(row) / scale > housingHeight / 2 { bodySpan = span }

    let leftReach = housingCentre - span.left
    let rightReach = span.right - housingCentre
    if abs(leftReach - rightReach) > tolerance { asymmetric += 1 }
}

if sampled == 0 {
    failures.append("expanded: nothing drawn — did the panel open?")
} else {
    if let topSpan {
        print(String(format: "  top row (with shoulders): %.1f .. %.1f", topSpan.left, topSpan.right))
    }
    if let bodySpan {
        print(String(format: "  body:                     %.1f .. %.1f  (width %.1f)",
                     bodySpan.left, bodySpan.right, bodySpan.right - bodySpan.left))
    }
    // Shoulders flare outward, so the top row must be wider than the body on both sides. If it is
    // not, they were clipped by the panel edge.
    if let topSpan, let bodySpan {
        if topSpan.left > bodySpan.left - tolerance || topSpan.right < bodySpan.right + tolerance {
            failures.append("expanded shoulders are missing or clipped at the panel edge")
        }
    }
    if asymmetric > 0 {
        failures.append("expanded shape is off-centre on \(asymmetric) row(s)")
    }
    print("  rows off-centre: \(asymmetric)")
}

// MARK: - Verdict

print("")
if failures.isEmpty {
    print("PASS — collapsed traces the housing, expanded is centred with intact shoulders")
    exit(0)
}
for failure in failures { print("FAIL — \(failure)") }
print("")
print("Spilling past the housing while collapsed: shoulders drawn on a shape that traces")
print("hardware. A constant offset every row: the panel origin, which AppKit rounds to whole")
print("points. Clipped or off-centre when expanded: the view placing an oversized child, where")
print("alignment and overflow interact — position by centre instead.")
exit(1)
