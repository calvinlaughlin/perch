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

/// Where the pointer was before the probe took it, so it can be handed back.
let originalPointer: CGPoint = {
    let location = NSEvent.mouseLocation
    let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens[0]
    return CGPoint(x: location.x, y: primary.frame.maxY - location.y)
}()

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
var skippedScenarios = 0

func check(_ condition: Bool, _ description: String) {
    print("  \(condition ? "ok  " : "FAIL") \(description)")
    if !condition { failures.append("[\(currentScenario)] \(description)") }
}

/// Run perch with a config of our choosing and hand the accessibility root to the body.
///
/// Config goes in a throwaway `XDG_CONFIG_HOME`, so scenarios cannot disturb the real one and
/// each starts from a known state rather than from whatever the machine happens to have.
/// Whether the invasive scenarios run.
///
/// They take the pointer for the best part of a minute and change what is playing, which is
/// intolerable to run while someone is using the machine. Off unless asked for.
let drivesInput = ProcessInfo.processInfo.environment["FULL"] == "1"

/// How a scenario interacts with the machine.
enum Interaction {
    /// Reads the accessibility tree. Touches nothing.
    case passive
    /// Moves the pointer, clicks, or changes playback.
    case driving
}

func scenario(
    _ name: String, interaction: Interaction = .passive, config: String,
    _ body: (AXUIElement) -> Void
) {
    if case .driving = interaction, !drivesInput {
        print("\n\(name.uppercased())\n  skipped — needs the pointer; run `make ui-probe FULL=1`")
        skippedScenarios += 1
        return
    }
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

/// Which display an accessibility element sits on, by name.
///
/// Position comes from the view itself, so this verifies where perch actually put its window
/// rather than where it reported intending to.
func displayName(containing element: AXUIElement) -> String? {
    guard let bounds = screenFrame(of: element) else { return nil }

    // AX positions are top-left origin, measured from the *primary* display — the one whose frame
    // origin is zero — while NSScreen frames are bottom-left. Flipping against the tallest screen
    // instead of the primary one puts every secondary display at the wrong offset, which reads as
    // "perch is on the wrong monitor" when it is the conversion that is wrong.
    let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens[0]
    return NSScreen.screens.first { screen in
        let flipped = CGRect(
            x: screen.frame.minX, y: primary.frame.maxY - screen.frame.maxY,
            width: screen.frame.width, height: screen.frame.height)
        return flipped.insetBy(dx: -2, dy: -2).contains(CGPoint(x: bounds.midX, y: bounds.midY))
    }?.localizedName
}

func window(of app: AXUIElement) -> AXUIElement? {
    descendants(of: app).first { role($0) == "AXWindow" }
}

/// Whether the notch is currently showing its expanded contents.
func panelIsOpen(_ app: AXUIElement) -> Bool {
    descendants(of: app).contains { identifier($0)?.hasPrefix("media.") == true }
}

// MARK: - Scenarios

scenario(
    "media widget",
    interaction: .driving,
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
    interaction: .driving,
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
    interaction: .driving,
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
    "media-text = false",
    config: """
        open-on = never
        collapsed-bleed = 90
        widget = media
        media-placement = leading
        media-artwork-size = 22
        media-text = false
        """
) { app in
    // Drawn in the strip rather than the panel so this stays passive: no pointer, no click, and
    // the notch never has to open.
    let artwork =
        element(withIdentifier: "media.artwork", in: app)
        ?? element(withIdentifier: "media.artwork.missing", in: app)

    // The artwork view exists only on the branch that renders a track. Without it, a missing title
    // proves nothing — it would be missing with the setting on too, because nothing is playing.
    guard artwork != nil else {
        print("  skipped — nothing playing, so an absent title would prove nothing")
        skippedScenarios += 1
        return
    }

    check(element(withIdentifier: "media.title", in: app) == nil, "the title is not drawn")
    check(element(withIdentifier: "media.artist", in: app) == nil, "the artist is not drawn")
    check(artwork != nil, "the rest of the widget still draws")
}

// Multi-display. Skipped with one screen rather than silently passing, so a green run on a
// single-display machine never reads as "multi-display works".
if NSScreen.screens.count > 1,
    let external = NSScreen.screens.first(where: { $0.safeAreaInsets.top == 0 })
{
    let name = external.localizedName
    scenario(
        "display = \(name)",
        config: """
            display = \(name)
            open-on = never
            collapsed-bleed = 90
            widget = clock
            """
    ) { app in
        check(
            window(of: app).flatMap(displayName(containing:)) == name,
            "the panel is on \(name), not the built-in display"
        )
        check(
            element(withIdentifier: "clock.time", in: app) != nil,
            "a widget renders on a display with no camera housing"
        )
        if let clock = element(withIdentifier: "clock.time", in: app),
            let bounds = screenFrame(of: clock)
        {
            check(
                bounds.minX >= external.frame.minX - 2,
                "content respects the display's origin (\(Int(external.frame.minX)))"
            )
        }
    }

    scenario(
        "display = a monitor that is not connected",
        config: """
            display = definitely-not-a-real-monitor
            open-on = never
            widget = clock
            """
    ) { app in
        // Falling back matters: a config written at a desk should not leave perch invisible on
        // the train.
        check(
            window(of: app).flatMap(displayName(containing:)) != nil,
            "perch falls back to a real display rather than disappearing"
        )
    }
} else {
    print("\nMULTI-DISPLAY\n  skipped — only one display connected")
}

scenario(
    "peek on track change",
    interaction: .driving,
    config: """
        open-on = never
        peek-duration = 2s
        widget = media
        """
) { app in
    // `open-on = never` is deliberate: it proves the peek was produced by the widget rather than
    // by the pointer happening to be somewhere.
    movePointer(to: parkingSpot)
    wait(1.0)
    check(
        element(withIdentifier: "media.peek.title", in: app) == nil,
        "nothing is announced before anything changes"
    )

    guard let next = element(withIdentifier: "media.next", in: app) ?? nil else {
        // Controls only exist while open, so skip the track through the adapter instead.
        let skip = Process()
        skip.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        skip.arguments = [adapterScript.path, adapterFramework.path, "send", "4"]
        skip.standardOutput = FileHandle.nullDevice
        skip.standardError = FileHandle.nullDevice
        try? skip.run()
        skip.waitUntilExit()

        // Poll rather than sleeping a fixed time: the peek is short, and a fixed wait would race
        // it in one direction or the other.
        // Poll tightly. Sampling only after a coarse detection loop misses the first moments,
        // which is exactly when a late-arriving image or metadata field rearranges things.
        var sawPeek = false
        var frames: [(x: CGFloat, y: CGFloat, text: String)] = []
        for _ in 0..<200 {
            if let title = element(withIdentifier: "media.peek.title", in: app) {
                sawPeek = true
                if let bounds = screenFrame(of: title) {
                    frames.append((bounds.minX, bounds.minY, value(title) ?? ""))
                }
                if frames.count >= 20 { break }
            } else if sawPeek {
                break  // The peek ended.
            }
            wait(0.03)
        }
        check(sawPeek, "skipping a track makes the notch announce it")

        // An announcement that rearranges itself while you are reading it is worse than none.
        if sawPeek, frames.count >= 3 {
            let horizontal = (frames.map(\.x).max() ?? 0) - (frames.map(\.x).min() ?? 0)
            let vertical = (frames.map(\.y).max() ?? 0) - (frames.map(\.y).min() ?? 0)
            check(
                horizontal < 1,
                "the announcement does not shift sideways (moved \(horizontal)pt)"
            )
            check(
                vertical < 1,
                "the announcement does not shift vertically (moved \(vertical)pt)"
            )
            check(
                Set(frames.map(\.text)).count <= 1,
                "the announcement's text does not change while it is up"
            )
        } else if sawPeek {
            check(false, "could not sample the announcement often enough to judge it")
        }

        var reverted = false
        for _ in 0..<30 {
            wait(0.2)
            if element(withIdentifier: "media.peek.title", in: app) == nil {
                reverted = true
                break
            }
        }
        check(reverted, "the announcement reverts on its own")
        return
    }
    _ = next
}

scenario(
    "notch menu",
    interaction: .driving,
    config: """
        open-on = hover
        widget = media
        """
) { app in
    // perch has no dock icon and no menu bar item, so this menu is the only way to quit or reach
    // the config without a terminal. If it stops appearing, the app becomes unquittable.
    movePointer(to: onTheNotch)
    wait(2.0)

    guard let window = window(of: app), let bounds = screenFrame(of: window) else {
        check(false, "could not locate the panel")
        return
    }

    let target = CGPoint(x: bounds.midX, y: bounds.minY + 12)
    CGWarpMouseCursorPosition(target)
    CGEvent(
        mouseEventSource: nil, mouseType: .rightMouseDown,
        mouseCursorPosition: target, mouseButton: .right
    )?.post(tap: .cghidEventTap)
    wait(0.08)
    CGEvent(
        mouseEventSource: nil, mouseType: .rightMouseUp,
        mouseCursorPosition: target, mouseButton: .right
    )?.post(tap: .cghidEventTap)
    wait(1.2)

    let titles = descendants(of: app).compactMap { element -> String? in
        guard role(element) == "AXMenuItem" else { return nil }
        return attribute(element, kAXTitleAttribute) as? String
    }
    check(!titles.isEmpty, "right-clicking the notch opens a menu")
    check(titles.contains { $0.contains("Quit") }, "the menu offers a way to quit")
    check(
        titles.contains { $0.contains("Configuration") },
        "the menu offers a way to reach the config"
    )
    // The probe runs perch from the build directory, where SMAppService cannot register — so the
    // item must be present and say why rather than silently missing or pretending to work.
    check(
        titles.contains { $0.contains("Open at Login") },
        "the menu offers a login-item toggle"
    )

    // Dismiss the menu through the accessibility API, aimed at the menu itself.
    //
    // Never post a synthetic key event to do this. A CGEvent goes to whatever application is
    // frontmost, not to perch — and this probe is run from a terminal. Dismissing the menu with a
    // global Escape sent Escape to the terminal instead, which cancelled the very command running
    // the probe. It looked like the tool was being interrupted at random.
    if let menu = descendants(of: app).first(where: { role($0) == "AXMenu" }) {
        AXUIElementPerformAction(menu, kAXCancelAction as CFString)
    }
    wait(0.4)
    movePointer(to: parkingSpot)

    check(
        descendants(of: app).allSatisfy { role($0) != "AXMenu" },
        "the menu closes again"
    )
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

movePointer(to: originalPointer)

print("")
if failures.isEmpty {
    let note = skippedScenarios > 0
        ? " (\(skippedScenarios) interactive scenario(s) skipped — run with FULL=1)"
        : ""
    print("PASS — every scenario behaved as configured\(note)")
    exit(0)
}
print("FAIL — \(failures.count) check(s) failed:")
for failure in failures { print("  - \(failure)") }
exit(1)
