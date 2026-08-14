import Foundation

/// The output volume, as the notch needs to draw it.
public struct VolumeState: Equatable, Sendable {

    /// The level, `0...1`.
    ///
    /// Clamped on the way in, because a device can report slightly outside the range.
    public var level: Double

    /// Whether output is muted.
    ///
    /// A muted device keeps its level — that is what unmuting restores.
    public var isMuted: Bool

    /// The output device's name, e.g. `MacBook Pro Speakers`, `AirPods Pro`.
    public var deviceName: String

    public init(level: Double, isMuted: Bool, deviceName: String) {
        self.level = min(max(level, 0), 1)
        self.isMuted = isMuted
        self.deviceName = deviceName
    }

    /// What is actually coming out: zero while muted, whatever the level says otherwise.
    ///
    /// Muting is not the same as turning the volume to zero, and the difference is visible — a
    /// muted device still knows the level it will return to.
    public var effectiveLevel: Double { isMuted ? 0 : level }

    /// Whether this differs from `other` in a way worth announcing.
    ///
    /// Compared on a rounded level rather than exactly. CoreAudio reports a float, and the hardware
    /// keys move in sixteenths with fine-grained steps in between, so two presses of the same key
    /// can produce values differing far below anything the notch could draw. Announcing those
    /// would open the panel for a change nobody made.
    public func isAnnouncable(comparedTo other: VolumeState?) -> Bool {
        guard let other else { return false }
        if isMuted != other.isMuted { return true }
        return Int((level * 100).rounded()) != Int((other.level * 100).rounded())
    }
}

/// Somewhere the output volume comes from.
///
/// A protocol for the same reason `MediaSource` is one: it is the seam that keeps CoreAudio out of
/// the widget, and it is what lets the widget be tested without a sound card.
public protocol VolumeSource: AnyObject, Sendable {

    /// Updates as the volume, the mute state, or the output device changes.
    ///
    /// Emits once on `start()` with the current state, so a subscriber knows where things stand
    /// without waiting for the user to press a key. That first value is **not** an announcement —
    /// see `HudWidget`, which drops it deliberately.
    var updates: AsyncStream<VolumeState> { get }

    /// Begin producing updates. Calling twice is a no-op.
    func start()

    /// Stop, releasing every listener. Calling twice is a no-op.
    func stop()
}
