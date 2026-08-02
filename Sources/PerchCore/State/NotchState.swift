/// What the notch is currently showing.
public enum NotchState: Equatable, Sendable {
    /// Tracing the hardware, showing at most a compact strip.
    case collapsed

    /// Briefly enlarged to announce something, without the user having asked.
    ///
    /// Used for things like a track change. A peek reverts on its own, and any real user
    /// intent — a hover or a click — supersedes it rather than queueing behind it.
    case peek

    /// Fully open.
    case expanded
}

/// What makes the notch open.
public enum OpenTrigger: String, Equatable, Sendable, CaseIterable {
    /// Open when the pointer rests on the notch.
    case hover

    /// Open only on an explicit click.
    case click

    /// Never open on its own; the notch stays collapsed unless something peeks.
    case never
}

/// What happens when scrolling reaches the end of the expanded widgets.
public enum ExpandedScroll: String, Equatable, Sendable, CaseIterable {

    /// Keep going. The widgets repeat, so there is no end to reach.
    ///
    /// Scrolling past the last one carries on in the same direction into the first, rather than
    /// turning round — so the motion never contradicts the gesture that caused it.
    case endless

    /// Return to the first widget, travelling back across the others to get there.
    ///
    /// Slower, and it says where you are: nothing else on a panel this size tells you the deck has
    /// a beginning, and arriving back at it is the only moment that can.
    case rewind
}

/// Things that can happen to the notch.
public enum NotchEvent: Equatable, Sendable {
    /// The pointer arrived over the notch. Records position; does not open anything.
    case pointerEntered

    /// The pointer has rested long enough to count as intent to open.
    ///
    /// Separate from `pointerEntered` so the controller can impose `open-delay` on *opening*
    /// without also delaying its knowledge of where the pointer is — which decides where a peek
    /// returns to when it expires.
    case hoverSettled

    case pointerExited
    case clicked

    /// A widget asked for attention.
    case peekRequested

    /// A peek ran its course.
    case peekExpired
}

/// The rules for when the notch is open.
///
/// Pure and synchronous: it takes an event and reports the resulting state. Timing — the hover
/// delay, how long a peek lasts — deliberately lives in the caller, because that lets every
/// transition be tested without waiting on a clock.
public struct NotchStateMachine: Equatable, Sendable {

    /// What opens the notch.
    ///
    /// Changing this mid-session, as a config reload does, is fine.
    public var openTrigger: OpenTrigger

    public private(set) var state: NotchState

    /// Whether the pointer is currently within the notch.
    ///
    /// Tracked separately from `state` because it decides where a peek returns to: if the pointer
    /// happens to be resting on the notch when a peek expires, collapsing out from under it would
    /// be wrong.
    public private(set) var pointerIsInside: Bool

    public init(openTrigger: OpenTrigger = .hover, state: NotchState = .collapsed) {
        self.openTrigger = openTrigger
        self.state = state
        self.pointerIsInside = false
    }

    /// Apply an event.
    ///
    /// - Returns: `true` if the state changed, so callers can skip redundant animation work.
    @discardableResult
    public mutating func handle(_ event: NotchEvent) -> Bool {
        let previous = state

        switch event {
        case .pointerEntered:
            pointerIsInside = true

        case .hoverSettled:
            // Re-check `pointerIsInside`: the delay this event is gated behind gives the pointer
            // time to leave, and a stale timer must not open a notch the user has walked away from.
            if openTrigger == .hover, pointerIsInside {
                state = .expanded
            }

        case .pointerExited:
            pointerIsInside = false
            // Leaving always closes, whatever opened it. A notch that stays open after the
            // pointer walks away is a notch covering your work.
            state = .collapsed

        case .clicked:
            switch openTrigger {
            case .never:
                break  // Explicitly inert.
            case .click, .hover:
                // Clicking toggles even in hover mode, so there is a way to dismiss the panel
                // without moving the pointer off it.
                state = (state == .expanded) ? .collapsed : .expanded
            }

        case .peekRequested:
            // Never downgrade a panel the user opened themselves.
            if state == .collapsed {
                state = .peek
            }

        case .peekExpired:
            if state == .peek {
                state = pointerIsInside && openTrigger == .hover ? .expanded : .collapsed
            }
        }

        return state != previous
    }
}
