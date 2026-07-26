#!/usr/bin/env swift
//
// NotchProbe — verify what perch actually draws against what the hardware actually is.
//
// Unit tests can prove NotchMetrics computes the right numbers. They cannot prove those numbers
// survive AppKit: window origins get rounded to whole points, hosting views apply safe-area
// insets, SwiftUI propagates its ideal size back into the window. Every one of those failed
// silently at some point during this project, and each produced pixels that were slightly wrong
// while every test stayed green.
//
// This closes that gap by measuring the screen. It reads the camera housing from NSScreen,
// screenshots the region, and reports for each row where perch's black shape actually lands.
//
// Usage:  perch must already be running, in normal (non-debug) drawing, and collapsed.
//         swift tools/NotchProbe.swift
//         make probe          # does the launching and cleanup for you
//
// Exits non-zero if any row deviates by more than half a backing pixel.

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
let housingHeight = screen.safeAreaInsets.top
let tolerance = 0.5 / scale

// MARK: - Capture

// Look a margin either side of the housing so shoulders spilling onto the menu bar are visible.
let margin: CGFloat = 20
let captureX = housingLeft - margin
let captureWidth = (housingRight - housingLeft) + margin * 2
let captureHeight = housingHeight + 8

let output = FileManager.default.temporaryDirectory
    .appendingPathComponent("perch-probe-\(UUID().uuidString).png")
defer { try? FileManager.default.removeItem(at: output) }

let capture = Process()
capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
// `-R` takes a top-left-origin rect, which is the same space the housing sits in.
capture.arguments = [
    "-x", "-R\(captureX),0,\(captureWidth),\(captureHeight)", output.path,
]
try capture.run()
capture.waitUntilExit()

guard
    capture.terminationStatus == 0,
    let source = CGImageSourceCreateWithURL(output as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    print("screen capture failed — grant Screen Recording permission to your terminal")
    exit(2)
}

// MARK: - Pixels

let width = image.width
let height = image.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)

guard
    let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
else {
    print("could not build a bitmap context")
    exit(2)
}
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

/// Whether a pixel is dark enough to be perch's black shape rather than wallpaper.
func isShape(x: Int, y: Int) -> Bool {
    let i = (y * width + x) * 4
    return Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2]) < 70
}

// MARK: - Report

// The invariant is one-sided, and deliberately so. A row *narrower* than the housing is fine:
// the camera housing is opaque, so anything inside it is hidden regardless — that is what the
// collapsed shape's bottom corner rounding looks like from here. A row *wider* than the housing
// is a defect by construction, because those pixels land on the menu bar where the user sees
// them. So: never exceed the housing, and match it exactly along the top edge.
print("housing: x \(housingLeft) .. \(housingRight) pt, height \(housingHeight)pt @\(scale)x")
print("tolerance: \(tolerance)pt (half a backing pixel)\n")
print(" ypt | drawn span            | vs housing")
print("-----+-----------------------+---------------------------")

var overruns = 0
var topEdgeProblem: String?
let rowsToCheck = Int(housingHeight * scale)

for row in 0..<min(rowsToCheck, height) {
    let y = CGFloat(row) / scale
    let columns = (0..<width).filter { isShape(x: $0, y: row) }

    guard let first = columns.first, let last = columns.last else {
        print(String(format: "%5.1f| (nothing drawn)", y))
        if row == 0 { topEdgeProblem = "nothing drawn on the top row" }
        continue
    }

    let left = captureX + CGFloat(first) / scale
    let right = captureX + CGFloat(last + 1) / scale
    let dLeft = left - housingLeft
    let dRight = right - housingRight

    let overruns_ = dLeft < -tolerance || dRight > tolerance
    if overruns_ { overruns += 1 }

    // The top row is the one place the shape must fill the housing exactly: too narrow there and
    // the wallpaper shows in the corners beside the notch.
    if row == 0, abs(dLeft) > tolerance || abs(dRight) > tolerance {
        topEdgeProblem = String(format: "top row spans %.1f..%.1f", left, right)
    }

    let note = overruns_ ? "<-- spills onto the menu bar" : ""
    print(
        String(
            format: "%5.1f| %7.1f .. %7.1f   | L%+5.1f R%+5.1f  %@",
            y, left, right, dLeft, dRight, note
        )
    )
}

print("")
if overruns == 0 && topEdgeProblem == nil {
    print("PASS — the shape fills the housing along the top and never spills past it")
    exit(0)
}

if let topEdgeProblem {
    print("FAIL — \(topEdgeProblem); expected \(housingLeft)..\(housingRight)")
}
if overruns > 0 {
    print("FAIL — \(overruns) row(s) draw outside the camera housing")
}
print("")
print("Rows wider than the housing are usually shoulders drawn on a shape that traces hardware;")
print("they should be suppressed. A constant offset on every row is usually the panel origin:")
print("AppKit rounds window origins to whole points and silently discards the fraction.")
exit(1)
