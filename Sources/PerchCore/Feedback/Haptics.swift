/// Which events make the trackpad tap.
///
/// Two events can tap, so four cases cover every combination exactly — there is no setting here
/// that cannot be expressed, and none that needs a second key to express it.
public enum HapticTrigger: String, Equatable, Sendable, CaseIterable {
    /// Nothing taps.
    case never

    /// Tap when the notch opens.
    case open

    /// Tap when a widget announces something.
    case peek

    /// Tap for both.
    case all

    /// Whether this trigger includes the notch opening.
    var includesOpen: Bool { self == .open || self == .all }

    /// Whether this trigger includes an announcement.
    var includesPeek: Bool { self == .peek || self == .all }
}

/// How the tap feels.
///
/// These are the three patterns macOS ships. Naming them rather than exposing an intensity is
/// deliberate: the system tunes each one to the hardware and to the user's trackpad settings, and a
/// hand-rolled intensity would fight that.
public enum HapticPattern: String, Equatable, Sendable, CaseIterable {
    /// A single firm tap. The heaviest of the three.
    case generic

    /// The light tap used when a dragged object snaps to a guide.
    case alignment

    /// The two-part tap of a detent moving between stops.
    case levelChange = "level-change"
}

/// When to tap and how, resolved from config.
///
/// Pure and synchronous, like `NotchStateMachine` and for the same reason: the decision is testable
/// without a trackpad, which matters more here than anywhere else in the app, because the effect
/// itself is invisible to every automated check. What can be verified is that the right pattern is
/// chosen for the right transition, so that is what lives here — separate from the AppKit call that
/// performs it.
public struct HapticPolicy: Equatable, Sendable {

    /// Which events tap.
    public var trigger: HapticTrigger

    /// How the tap feels.
    public var pattern: HapticPattern

    public init(trigger: HapticTrigger = .never, pattern: HapticPattern = .alignment) {
        self.trigger = trigger
        self.pattern = pattern
    }

    /// The pattern to perform for a state change, or nil if this one is silent.
    ///
    /// Only transitions *into* an open or announcing state tap. Closing does not: by the time the
    /// notch collapses the pointer has already left it, and a tap chasing the pointer away carries
    /// no information — you are looking somewhere else by then.
    public func pattern(from previous: NotchState, to current: NotchState) -> HapticPattern? {
        guard previous != current else { return nil }

        switch current {
        case .expanded:
            // Reached from `.collapsed` by a hover or click, and from `.peek` when the pointer
            // settles on an announcement that is already up. Both are the notch opening.
            return trigger.includesOpen ? pattern : nil

        case .peek:
            return trigger.includesPeek ? pattern : nil

        case .collapsed:
            return nil
        }
    }
}
