#!/usr/bin/env swift
//
// UIProbe — verify perch's interface by inspecting and driving it, not by looking at it.
//
// This exists because "it works" was once claimed on evidence that could not support it: a
// process existed, a screenshot contained the right words, CPU was zero. All true, and all
// compatible with every button being dead — which they were. A screenshot shows a steady state.
// It cannot show whether a control does anything, and it cannot show content arriving a beat
// after the surface it is meant to be part of.
//
// So this reads the accessibility tree — the real view hierarchy, the same one a screen reader
// sees — and presses controls through it. A control that is not wired up cannot be pressed, so a
// dead button fails here by construction rather than by someone noticing.
//
// Usage:  make ui-probe
//
// Needs Accessibility permission for the terminal running it.

import AppKit
import ApplicationServices
import Foundation

// MARK: - Accessibility

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
        return nil
    }
    return value
}

func children(of element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func descendants(of root: AXUIElement, limit: Int = 400) -> [AXUIElement] {
    var found: [AXUIElement] = []
    var queue = [root]
    while !queue.isEmpty, found.count < limit {
        let element = queue.removeFirst()
        found.append(element)
        queue.append(contentsOf: children(of: element))
    }
    return found
}

func identifier(_ element: AXUIElement) -> String? { attribute(element, "AXIdentifier") as? String }
func role(_ element: AXUIElement) -> String { attribute(element, kAXRoleAttribute) as? String ?? "?" }
func value(_ element: AXUIElement) -> String? { attribute(element, kAXValueAttribute) as? String }

/// The whole tree, as one line per element. Used for reporting a failure usefully.
func outline(_ root: AXUIElement) -> String {
    descendants(of: root)
        .map { element in
            let bits = [role(element), value(element).map { "value=\($0)" }, identifier(element)]
            return "    " + bits.compactMap { $0 }.joined(separator: " ")
        }
        .joined(separator: "\n")
}

func element(withIdentifier wanted: String, in root: AXUIElement) -> AXUIElement? {
    descendants(of: root).first { identifier($0) == wanted }
}

// MARK: - Pointer

/// Where an element actually is on screen, straight from the accessibility tree.
///
/// This is what makes a real click reliable: the coordinates come from the view itself rather
/// than from guessing at a layout, so the probe stays correct when the layout changes.
func screenFrame(of element: AXUIElement) -> CGRect? {
    var positionValue: AnyObject?
    var sizeValue: AnyObject?
    guard
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
            == .success,
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
        let positionValue, let sizeValue
    else { return nil }

    var origin = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
    AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    return CGRect(origin: origin, size: size)
}

/// Click where a real user would, with real events.
///
/// `AXUIElementPerformAction` is not a substitute: it invokes the control's action directly and
/// therefore passes even when every mouse event is being swallowed before it reaches the view.
/// That is exactly the bug this probe exists to catch, and an earlier version of it missed the
/// bug for precisely this reason.
func click(at point: CGPoint) {
    CGWarpMouseCursorPosition(point)
    CGEvent(
        mouseEventSource: nil, mouseType: .mouseMoved,
        mouseCursorPosition: point, mouseButton: .left
    )?.post(tap: .cghidEventTap)
    wait(0.15)
    CGEvent(
        mouseEventSource: nil, mouseType: .leftMouseDown,
        mouseCursorPosition: point, mouseButton: .left
    )?.post(tap: .cghidEventTap)
    wait(0.06)
    CGEvent(
        mouseEventSource: nil, mouseType: .leftMouseUp,
        mouseCursorPosition: point, mouseButton: .left
    )?.post(tap: .cghidEventTap)
}

func movePointer(to point: CGPoint) {
    CGWarpMouseCursorPosition(point)
    CGEvent(
        mouseEventSource: nil, mouseType: .mouseMoved,
        mouseCursorPosition: point, mouseButton: .left
    )?.post(tap: .cghidEventTap)
}

func wait(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }

// MARK: - Setup

guard AXIsProcessTrusted() else {
    print("FAIL — no Accessibility permission for this terminal.")
    print("Grant it in System Settings > Privacy & Security > Accessibility, then re-run.")
    exit(3)
}

guard
    let screen = NSScreen.screens.first(where: {
        $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil
    })
else {
    print("no display with a camera housing — nothing to probe")
    exit(0)
}

let housingCentre =
    screen.frame.minX + (screen.auxiliaryTopLeftArea?.width ?? 0)
    + (screen.frame.width - (screen.auxiliaryTopLeftArea?.width ?? 0)
        - (screen.auxiliaryTopRightArea?.width ?? 0)) / 2
let onTheNotch = CGPoint(x: housingCentre, y: screen.safeAreaInsets.top / 2)
let parkingSpot = CGPoint(x: screen.frame.midX, y: screen.frame.maxY - 200)

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let binary =
    CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "build/perch.app/Contents/MacOS/perch"
let adapterScript = root.appendingPathComponent(
    "build/perch.app/Contents/Resources/mediaremote-adapter.pl")
let adapterFramework = root.appendingPathComponent(
    "build/perch.app/Contents/Frameworks/MediaRemoteAdapter.framework")

/// Ask the system what is playing, independently of perch.
///
/// This is the ground truth a button press is checked against: perch's own view of playback would
/// happily agree with itself whether or not the press reached the player.
func playbackIsPlaying() -> Bool? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    task.arguments = [adapterScript.path, adapterFramework.path, "get"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice
    guard (try? task.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()

    guard
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let playing = object["playing"] as? Bool
    else { return nil }
    return playing
}

// MARK: - Launch

_ = try? Process.run(URL(fileURLWithPath: "/usr/bin/pkill"), arguments: ["-x", "perch"])
wait(0.6)
movePointer(to: parkingSpot)

let perch = Process()
perch.executableURL = URL(fileURLWithPath: binary)
perch.standardOutput = FileHandle.nullDevice
perch.standardError = FileHandle.nullDevice
do { try perch.run() } catch {
    print("FAIL — could not launch \(binary): \(error)")
    exit(2)
}
defer {
    perch.terminate()
    movePointer(to: parkingSpot)
}
wait(2.0)

let app = AXUIElementCreateApplication(perch.processIdentifier)
var failures: [String] = []
func check(_ condition: Bool, _ description: String) {
    print("  \(condition ? "ok  " : "FAIL") \(description)")
    if !condition { failures.append(description) }
}

// MARK: - The panel opens and is populated

print("OPENING")
movePointer(to: onTheNotch)
wait(2.5)

let elements = descendants(of: app)
check(elements.contains { role($0) == "AXWindow" }, "a window exists")
check(
    element(withIdentifier: "media.title", in: app) != nil
        || elements.contains { role($0) == "AXStaticText" && !(value($0) ?? "").isEmpty },
    "the media widget shows a title"
)
check(
    element(withIdentifier: "media.artwork.missing", in: app) == nil,
    "artwork is decoded, not a placeholder"
)
check(element(withIdentifier: "media.toggle", in: app) != nil, "a play/pause control exists")
check(element(withIdentifier: "media.next", in: app) != nil, "a next-track control exists")
check(element(withIdentifier: "media.previous", in: app) != nil, "a previous-track control exists")

// MARK: - Controls actually do something
//
// The bug this catches: perch's own mouseDown swallowed every click, so buttons never fired and
// pressing one closed the panel. Both effects are checked.

print("CLICKING PLAY/PAUSE (real mouse events, at the position the view reports)")
if let toggle = element(withIdentifier: "media.toggle", in: app),
    let bounds = screenFrame(of: toggle),
    let before = playbackIsPlaying()
{
    click(at: CGPoint(x: bounds.midX, y: bounds.midY))
    wait(1.5)

    let after = playbackIsPlaying()
    check(
        after != nil && after != before,
        "a real click changes playback (\(before) -> \(after.map(String.init(describing:)) ?? "nil"))"
    )

    // The panel must survive being used. It previously collapsed on any click, because the
    // notch's own mouseDown consumed the event instead of forwarding it.
    check(
        element(withIdentifier: "media.toggle", in: app) != nil,
        "the panel stays open after a control is clicked"
    )

    // Put playback back where it was.
    if let again = element(withIdentifier: "media.toggle", in: app),
        let againBounds = screenFrame(of: again)
    {
        click(at: CGPoint(x: againBounds.midX, y: againBounds.midY))
        wait(1.0)
    }
} else {
    check(false, "could not locate the play/pause control or read playback state")
}

// MARK: - Reopening is instant
//
// The bug this catches: tearing the helper down on close meant every reopen showed an empty panel
// that filled in seconds later, piecemeal.

print("CLOSING AND REOPENING")
movePointer(to: parkingSpot)
wait(1.5)
check(element(withIdentifier: "media.toggle", in: app) == nil, "the panel closes")

movePointer(to: onTheNotch)
wait(0.7)  // Deliberately short: content should already be there, not fetched on demand.
check(
    element(withIdentifier: "media.toggle", in: app) != nil,
    "content is present within 700ms of reopening"
)
check(
    element(withIdentifier: "media.artwork.missing", in: app) == nil,
    "artwork survives a close/reopen rather than reloading"
)

// MARK: - Verdict

print("")
if failures.isEmpty {
    print("PASS — the interface is present, its controls work, and reopening is instant")
    exit(0)
}
print("FAIL — \(failures.count) check(s) failed:")
for failure in failures { print("  - \(failure)") }
print("")
print("accessibility tree at the end of the run:")
print(outline(app))
exit(1)
