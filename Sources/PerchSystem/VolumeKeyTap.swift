import AppKit
import CoreGraphics
import Foundation

/// Intercepts the volume keys before macOS sees them.
///
/// This is the only way to stop the system drawing its own overlay. The obvious approach — taking
/// `com.apple.OSDUIHelper` out of service — cannot work: `launchctl bootout` fails with
/// `150: Operation not permitted while System Integrity Protection is engaged`, and SIP is on by
/// default. There is no API for "do not show the OSD".
///
/// So the overlay is not suppressed; it is never asked for. The key event is consumed here, macOS
/// never learns a volume key was pressed, and perch applies the change itself through
/// ``VolumeControl``.
///
/// **This needs Accessibility.** An event tap without it fails to create, which is why ``start()``
/// reports whether it worked rather than assuming. Denied is a normal state, not an error: perch
/// falls back to watching the volume instead of owning it, and the system overlay comes back.
public final class VolumeKeyTap: @unchecked Sendable {

    /// A volume key, as the tap saw it.
    public enum Key: Sendable {
        case up
        case down
        case mute
    }

    /// Called on the main thread for each key *press* — repeats included, key-up ignored.
    ///
    /// The `fine` flag is Shift-Option, which macOS uses for quarter-sized steps.
    public var onKey: (@MainActor (Key, _ fine: Bool) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    public init() {}

    deinit { stop() }

    /// Whether perch is allowed to create an event tap.
    ///
    /// - Parameter prompt: show the system's "grant access" dialogue if not yet trusted.
    /// - Returns: whether an event tap may be created.
    public static func isPermitted(prompt: Bool = false) -> Bool {
        // Spelled out rather than via `kAXTrustedCheckOptionPrompt`, which is an imported `var` and
        // so not concurrency-safe to reference. The value is API and cannot change.
        let options = ["AXTrustedCheckOptionPrompt": prompt]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// `NX_SYSDEFINED`.
    ///
    /// Swift's `CGEventType` does not name this case, though the tap delivers it.
    private static let systemDefined: UInt32 = 14

    /// Begin intercepting.
    ///
    /// Calling twice is a no-op.
    ///
    /// - Returns: whether the tap is running. `false` means Accessibility has not been granted, and
    ///   the caller should carry on without suppression rather than treat it as fatal.
    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }

        // `systemDefined` (14) is what the volume, brightness and media keys arrive as. Not
        // `keyDown` — these never appear as ordinary key events.
        let mask = CGEventMask(1 << Self.systemDefined)

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, context in
                    guard let context else { return Unmanaged.passUnretained(event) }
                    let tap = Unmanaged<VolumeKeyTap>.fromOpaque(context).takeUnretainedValue()
                    return tap.handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else { return false }

        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// Stop intercepting, giving the keys back to macOS.
    ///
    /// Calling twice is a no-op.
    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        tap = nil
    }

    /// Decide whether to swallow an event, on the run loop it was tapped from.
    private func handle(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // A slow callback gets the tap switched off by the system. Re-arming is the difference
        // between "the volume keys stopped working" and a momentary hiccup.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard type.rawValue == Self.systemDefined,
            let key = Self.volumeKey(in: event)
        else { return Unmanaged.passUnretained(event) }

        guard key.isDown else { return nil }  // swallow key-up too, or macOS still reacts

        let handler = onKey
        MainActor.assumeIsolated { handler?(key.key, key.fine) }

        // nil consumes the event. This is the whole mechanism: macOS never sees the press, so it
        // never draws the overlay and never changes the volume.
        return nil
    }

    /// Pick a volume key out of a system-defined event.
    ///
    /// The payload is packed into `data1`: the key code in the high 16 bits, and the state in the
    /// next byte down. Subtype 8 is `NX_SUBTYPE_AUX_CONTROL_BUTTONS` — anything else is a
    /// different sort of system event entirely and must be passed straight through.
    private static func volumeKey(in event: CGEvent) -> (key: Key, isDown: Bool, fine: Bool)? {
        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else {
            return nil
        }

        let data = nsEvent.data1
        let code = Int32((data & 0xFFFF_0000) >> 16)
        let isDown = ((data & 0xFF00) >> 8) == 0x0A

        let key: Key
        switch code {
        case 0: key = .up  // NX_KEYTYPE_SOUND_UP
        case 1: key = .down  // NX_KEYTYPE_SOUND_DOWN
        case 7: key = .mute  // NX_KEYTYPE_MUTE
        default: return nil
        }

        let fine =
            nsEvent.modifierFlags.contains(.shift)
            && nsEvent.modifierFlags.contains(.option)

        return (key, isDown, fine)
    }
}
