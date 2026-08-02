import AppKit
import PerchCore

/// Performs a tap on the trackpad.
///
/// Thin on purpose. Deciding *whether* to tap is `HapticPolicy`, which is pure and tested; this is
/// only the AppKit call that policy cannot make from `PerchCore`. Holding the call behind a closure
/// lets a test observe what was asked for, which is as close to verifying a haptic as software gets
/// — the tap itself is felt, not observed.
///
/// `NSHapticFeedbackManager` is silently inert without a Force Touch trackpad, and respects the
/// user's "Force Click and haptic feedback" setting. Both are the right behaviour and neither is
/// something to work around: a user who turned haptics off system-wide meant it.
@MainActor
public struct HapticEngine {

    private let performer: (HapticPattern) -> Void

    public init(performer: @escaping (HapticPattern) -> Void) {
        self.performer = performer
    }

    /// The real trackpad.
    public static let system = HapticEngine { pattern in
        NSHapticFeedbackManager.defaultPerformer.perform(
            pattern.patternType,
            // `.now` rather than `.drawCompleted`: the notch animates open over several frames, and
            // deferring to the end of a drawing cycle would put the tap somewhere inside that
            // animation rather than at the moment the state actually changed.
            performanceTime: .now
        )
    }

    /// A no-op engine, for tests and for headless runs.
    public static let silent = HapticEngine { _ in }

    /// Tap, if this transition calls for one under the given policy.
    public func perform(_ policy: HapticPolicy, from previous: NotchState, to current: NotchState) {
        guard let pattern = policy.pattern(from: previous, to: current) else { return }
        performer(pattern)
    }

    /// Tap for a card reaching the next stop on the spindle.
    public func performCardTurn(_ policy: HapticPolicy) {
        guard let pattern = policy.patternForCardTurn() else { return }
        performer(pattern)
    }
}

extension HapticPattern {
    /// The AppKit pattern this spelling names.
    ///
    /// Written as an exhaustive switch with no `default`, so adding a pattern to the config enum
    /// fails to compile until it is mapped here rather than silently falling back to `.generic`.
    var patternType: NSHapticFeedbackManager.FeedbackPattern {
        switch self {
        case .generic: .generic
        case .alignment: .alignment
        case .levelChange: .levelChange
        }
    }
}
