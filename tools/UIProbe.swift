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

// MARK: - Running perch under a scenario

var failures: [String] = []
var currentScenario = ""

func check(_ condition: Bool, _ description: String) {
    print("  \(condition ? "ok  " : "FAIL") \(description)")
    if !condition { failures.append("[\(currentScenario)] \(description)") }
}

/// Run perch with a config of our choosing and hand the accessibility root to the body.
///
/// Config goes in a throwaway `XDG_CONFIG_HOME`, so scenarios cannot disturb the real one and
/// each starts from a known state rather than from whatever the machine happens to have.
func scenario(_ name: String, config: String, _ body: (AXUIElement) -> Void) {
    currentScenario = name
    print("\n\(name.uppercased())")

    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("perch-probe-\(UUID().uuidString)", isDirectory: true)
    let directory = home.appendingPathComponent("perch", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? config.write(
        to: directory.appendingPathComponent("config"), atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: home) }

    _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/pkill"), arguments: ["-x", "perch"])
    wait(0.8)
    movePointer(to: parkingSpot)

    let perch = Process()
    perch.executableURL = URL(fileURLWithPath: binary)
    perch.standardOutput = FileHandle.nullDevice
    perch.standardError = FileHandle.nullDevice
    var environment = ProcessInfo.processInfo.environment
    environment["XDG_CONFIG_HOME"] = home.path
    perch.environment = environment

    do { try perch.run() } catch {
        check(false, "could not launch perch: \(error)")
        return
    }
    defer {
        perch.terminate()
        wait(0.5)
        movePointer(to: parkingSpot)
    }
    wait(2.0)

    body(AXUIElementCreateApplication(perch.processIdentifier))
}

/// Whether the notch is currently showing its expanded contents.
func panelIsOpen(_ app: AXUIElement) -> Bool {
    descendants(of: app).contains { identifier($0)?.hasPrefix("media.") == true }
}

// MARK: - Scenarios

scenario(
    "media widget",
    config: """
        open-on = hover
        widget = media
        """
) { app in
    let elements = descendants(of: app)
    check(elements.contains { role($0) == "AXWindow" }, "a window exists")
    check(!panelIsOpen(app), "the panel starts closed")

    movePointer(to: onTheNotch)
    wait(2.5)

    check(
        element(withIdentifier: "media.title", in: app) != nil
            || descendants(of: app).contains {
                role($0) == "AXStaticText" && !(value($0) ?? "").isEmpty
            },
        "the media widget shows a title"
    )
    check(
        element(withIdentifier: "media.artwork.missing", in: app) == nil,
        "artwork is decoded, not a placeholder"
    )
    check(element(withIdentifier: "media.toggle", in: app) != nil, "a play/pause control exists")
    check(element(withIdentifier: "media.next", in: app) != nil, "a next-track control exists")

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
        check(panelIsOpen(app), "the panel stays open after a control is clicked")

        if let again = element(withIdentifier: "media.toggle", in: app),
            let againBounds = screenFrame(of: again)
        {
            click(at: CGPoint(x: againBounds.midX, y: againBounds.midY))
            wait(1.0)
        }
    } else {
        check(false, "could not locate the play/pause control or read playback state")
    }

    movePointer(to: parkingSpot)
    wait(1.5)
    check(!panelIsOpen(app), "the panel closes")

    movePointer(to: onTheNotch)
    wait(0.7)
    check(panelIsOpen(app), "content is present within 700ms of reopening")
    check(
        element(withIdentifier: "media.artwork.missing", in: app) == nil,
        "artwork survives a close/reopen rather than reloading"
    )
    movePointer(to: parkingSpot)
}

scenario(
    "open-on = click",
    config: """
        open-on = click
        widget = media
        """
) { app in
    movePointer(to: onTheNotch)
    wait(2.0)
    check(!panelIsOpen(app), "hovering does not open the panel")

    click(at: onTheNotch)
    wait(1.5)
    check(panelIsOpen(app), "clicking opens the panel")

    click(at: onTheNotch)
    wait(1.0)
    check(!panelIsOpen(app), "clicking again closes it")
    movePointer(to: parkingSpot)
}

scenario(
    "open-on = never",
    config: """
        open-on = never
        widget = media
        """
) { app in
    movePointer(to: onTheNotch)
    wait(2.0)
    check(!panelIsOpen(app), "hovering does not open the panel")

    click(at: onTheNotch)
    wait(1.5)
    check(!panelIsOpen(app), "clicking does not open the panel either")
    movePointer(to: parkingSpot)
}

scenario(
    "collapsed strip",
    config: """
        open-on = never
        collapsed-bleed = 90
        widget = clock
        clock-placement = trailing
        clock-seconds = true
        """
) { app in
    // This layout path had never rendered: media defaults to `expanded`, and with no bleed the
    // strips have no room, so nothing had ever been drawn beside the housing.
    check(
        element(withIdentifier: "clock.time", in: app) != nil,
        "a strip widget renders while the notch is collapsed"
    )

    if let clock = element(withIdentifier: "clock.time", in: app),
        let bounds = screenFrame(of: clock)
    {
        check(bounds.width > 0 && bounds.height > 0, "the strip widget has a real size")
        check(
            bounds.minX > housingCentre,
            "a trailing widget sits right of the camera housing"
        )
        check(
            bounds.maxY <= screen.safeAreaInsets.top + 1,
            "the strip widget stays within the collapsed shape"
        )
    } else {
        check(false, "could not locate the strip widget")
    }
}

scenario(
    "unknown widget",
    config: """
        widget =
        widget = wibble
        """
) { app in
    // A config naming a widget that does not exist must not take the app down with it.
    check(descendants(of: app).contains { role($0) == "AXWindow" }, "perch still runs")
}

// MARK: - Verdict

print("")
if failures.isEmpty {
    print("PASS — every scenario behaved as configured")
    exit(0)
}
print("FAIL — \(failures.count) check(s) failed:")
for failure in failures { print("  - \(failure)") }
exit(1)
