import CoreGraphics

/// Turns a stream of scroll events into discrete card turns.
///
/// Pure and synchronous, like `NotchStateMachine` and for the same reason: scrolling is the one
/// input that cannot be reasoned about by looking at it. A flick is dozens of events arriving over
/// hundreds of milliseconds, and whether it should turn one card or four is a question about that
/// whole sequence — which a test can pose in a loop and a person cannot pose at all without a
/// trackpad and a lot of patience.
public struct ScrollPager: Equatable, Sendable {

    /// Where a scroll event sits in a gesture.
    ///
    /// Modelled rather than taken from `NSEvent` so this stays in `PerchCore`, and because the
    /// distinction that matters — fingers versus coasting — is not obvious from AppKit's two
    /// separate phase masks.
    public enum Phase: Equatable, Sendable {
        /// Fingers have landed and the gesture is starting.
        case began

        /// Fingers are moving.
        case changed

        /// Fingers have left. Anything after this is the system's doing, not the user's.
        case ended

        /// The system coasting after the fingers left.
        case momentum

        /// A device with no gesture phases at all — a wheel mouse, one detent per event.
        case discrete
    }

    /// How much scrolling adds up to one card.
    ///
    /// Small enough that a deliberate flick turns, large enough that the stray pixels a trackpad
    /// emits while a hand rests on it do not.
    public var threshold: CGFloat

    /// Scroll accumulated since the last turn.
    private var accumulated: CGFloat = 0

    /// Whether the current gesture has already turned a card.
    private var turnedThisGesture = false

    public init(threshold: CGFloat = 20) {
        self.threshold = threshold
    }

    /// Feed one scroll event.
    ///
    /// - Returns: `1` to turn forward, `-1` back, `0` to do nothing.
    public mutating func scrolled(delta: CGFloat, phase: Phase) -> Int {
        switch phase {
        case .momentum:
            // The coast never turns a card, and this is the bug worth naming. Momentum keeps
            // arriving for the better part of a second after the fingers have gone, and a
            // threshold that resets on every turn will cross it again and again on that tail
            // alone — so one flick walks the whole way round the wheel. Dropping momentum outright
            // is what makes a flick mean one card. It also matches what a rolodex does: the cards
            // stop when your hand stops.
            return 0

        case .began:
            accumulated = 0
            turnedThisGesture = false
            return turn(by: delta, latching: true)

        case .changed:
            // One card per gesture, however far the fingers travel. A long drag turning four cards
            // sounds reasonable and feels awful on a wheel of two.
            guard !turnedThisGesture else { return 0 }
            return turn(by: delta, latching: true)

        case .ended:
            accumulated = 0
            turnedThisGesture = false
            return 0

        case .discrete:
            // A wheel mouse has no gesture to latch onto — every event is its own detent, and
            // keeping the wheel spinning is meant to keep turning cards.
            return turn(by: delta, latching: false)
        }
    }

    /// Add to the running total and report a turn if it has gone far enough.
    private mutating func turn(by delta: CGFloat, latching: Bool) -> Int {
        // Reversing direction abandons whatever was building up, so a nudge back the other way
        // never sticks around to be spent on a later scroll.
        //
        // A zero delta is not a reversal. It has no direction to disagree with, and a trackpad
        // emits one whenever a finger rests still for a frame — treating that as a change of mind
        // throws away a scroll the user is in the middle of making, so a slow deliberate movement
        // keeps losing its total and never reaches the threshold at all.
        if delta != 0, accumulated != 0, (delta < 0) != (accumulated < 0) { accumulated = 0 }
        accumulated += delta

        guard abs(accumulated) >= threshold else { return 0 }

        // Direction follows the finger: under macOS "natural" scrolling, fingers moving left drag
        // the deck left and bring the next card in from the right, which is a negative delta.
        let step = accumulated < 0 ? 1 : -1
        accumulated = 0
        if latching { turnedThisGesture = true }
        return step
    }
}
