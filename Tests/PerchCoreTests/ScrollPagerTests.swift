import CoreGraphics
import Testing

@testable import PerchCore

/// Replays a scroll the way a device actually emits one.
extension ScrollPager {

    /// A trackpad swipe: fingers down, a run of movement, fingers up, then the system coasting.
    ///
    /// The coast is the part that matters. macOS keeps sending events for the better part of a
    /// second after the fingers have gone, and they are indistinguishable from finger movement by
    /// delta alone — which is exactly why this is modelled rather than described.
    mutating func flick(
        deltaPerEvent: CGFloat, fingerEvents: Int, momentumEvents: Int
    ) -> [Int] {
        var turns: [Int] = []
        turns.append(scrolled(delta: deltaPerEvent, phase: .began))
        for _ in 1..<max(fingerEvents, 1) {
            turns.append(scrolled(delta: deltaPerEvent, phase: .changed))
        }
        turns.append(scrolled(delta: 0, phase: .ended))
        for _ in 0..<momentumEvents {
            turns.append(scrolled(delta: deltaPerEvent, phase: .momentum))
        }
        return turns.filter { $0 != 0 }
    }
}

@Suite("Turning cards by scrolling")
struct ScrollPagerTests {

    @Test("One flick turns one card, however hard it is thrown")
    func hardFlickTurnsOnce() {
        // The bug this type was extracted for. A threshold that resets on every turn keeps being
        // crossed by the momentum tail, so a single hard flick walks the whole way round the wheel.
        var pager = ScrollPager()
        let turns = pager.flick(deltaPerEvent: -40, fingerEvents: 12, momentumEvents: 30)

        #expect(turns == [1])
    }

    @Test("A gentle flick still turns a card")
    func gentleFlickTurns() {
        var pager = ScrollPager()
        #expect(pager.flick(deltaPerEvent: -8, fingerEvents: 4, momentumEvents: 2) == [1])
    }

    @Test("Resting a hand on the trackpad turns nothing")
    func restingHandIsQuiet() {
        var pager = ScrollPager()
        #expect(pager.flick(deltaPerEvent: -1, fingerEvents: 3, momentumEvents: 0).isEmpty)
    }

    @Test("Momentum on its own never turns a card")
    func momentumAloneIsInert() {
        var pager = ScrollPager()
        var turns: [Int] = []
        for _ in 0..<50 { turns.append(pager.scrolled(delta: -50, phase: .momentum)) }

        #expect(turns.allSatisfy { $0 == 0 })
    }

    @Test("Flicking twice turns twice")
    func separateFlicksEachTurn() {
        // The latch has to lift when the fingers leave, or the wheel jams after one card.
        var pager = ScrollPager()
        #expect(pager.flick(deltaPerEvent: -40, fingerEvents: 8, momentumEvents: 20) == [1])
        #expect(pager.flick(deltaPerEvent: -40, fingerEvents: 8, momentumEvents: 20) == [1])
    }

    @Test("Flicking the other way turns back")
    func flickBackTurnsBack() {
        var pager = ScrollPager()
        #expect(pager.flick(deltaPerEvent: 40, fingerEvents: 8, momentumEvents: 20) == [-1])
    }

    @Test("Fingers moving left bring the next card in from the right")
    func directionFollowsTheFinger() {
        // Under macOS "natural" scrolling a negative delta drags the deck left, which advances.
        var pager = ScrollPager()
        #expect(pager.scrolled(delta: -30, phase: .began) == 1)

        var back = ScrollPager()
        #expect(back.scrolled(delta: 30, phase: .began) == -1)
    }

    @Test("Reversing mid-gesture abandons what had built up")
    func reversalWipesTheTotal() {
        var pager = ScrollPager()

        // Just under the threshold, so nothing turns yet.
        #expect(pager.scrolled(delta: -19, phase: .began) == 0)

        // A nudge back the other way. This has to discard the 19, not net against it.
        #expect(pager.scrolled(delta: 4, phase: .changed) == 0)

        // The discriminating one. Without the wipe the running total here would be -34 and would
        // turn a card; with it this is a fresh -19 and must not. A stale total surviving a
        // reversal is how a scroll ends up turning on a movement the user already changed
        // their mind about.
        #expect(pager.scrolled(delta: -19, phase: .changed) == 0)
    }

    @Test("A gesture whose end never arrives leaves the deck dead")
    func swallowedEndJamsTheLatch() {
        // Not a wish, a warning. The latch is released by `.ended` and nothing else, so anything
        // upstream that filters events has to let boundaries through — an axis filter judging
        // events by direction will drop `.began` and `.ended`, which carry no direction at all.
        //
        // This is pinned as a test because the symptom is so misleading: one swipe works, every
        // later swipe silently does nothing, and the pager itself is behaving exactly as written.
        var pager = ScrollPager()
        #expect(pager.scrolled(delta: -30, phase: .began) == 1)

        // `.ended` never delivered. A second gesture arriving as bare `.changed` events cannot turn.
        #expect(pager.scrolled(delta: -30, phase: .changed) == 0)
        #expect(pager.scrolled(delta: -30, phase: .changed) == 0)

        // Delivering the boundary revives it.
        _ = pager.scrolled(delta: 0, phase: .ended)
        #expect(pager.scrolled(delta: -30, phase: .changed) == 1)
    }

    @Test("A wheel mouse keeps turning as it keeps spinning")
    func wheelIsNotLatched() {
        // A wheel emits no gesture phases, so there is no gesture to latch onto and nothing to
        // release the latch either — latching these would jam the wheel after one card.
        var pager = ScrollPager()
        var turns: [Int] = []
        for _ in 0..<6 { turns.append(pager.scrolled(delta: -25, phase: .discrete)) }

        #expect(turns == [1, 1, 1, 1, 1, 1])
    }

    @Test("A slow wheel needs several detents to turn a card")
    func slowWheelAccumulates() {
        var pager = ScrollPager()
        #expect(pager.scrolled(delta: -6, phase: .discrete) == 0)
        #expect(pager.scrolled(delta: -6, phase: .discrete) == 0)
        #expect(pager.scrolled(delta: -6, phase: .discrete) == 0)
        #expect(pager.scrolled(delta: -6, phase: .discrete) == 1)
    }

    @Test("A long drag still turns only one card")
    func longDragTurnsOnce() {
        // Four cards on one continuous movement sounds reasonable and feels awful on a wheel of two.
        var pager = ScrollPager()
        #expect(pager.flick(deltaPerEvent: -30, fingerEvents: 40, momentumEvents: 0) == [1])
    }
}
