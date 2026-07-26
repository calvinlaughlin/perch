import Testing

@testable import PerchCore

@Suite("Hover behaviour")
struct HoverTriggerTests {
    @Test("A settled hover opens the notch")
    func settledHoverOpens() {
        var machine = NotchStateMachine(openTrigger: .hover)
        machine.handle(.pointerEntered)

        let changed = machine.handle(.hoverSettled)

        #expect(changed)
        #expect(machine.state == .expanded)
    }

    @Test("Arriving alone does not open the notch")
    func arrivingAloneDoesNotOpen() {
        // open-delay lives between these two events; opening on arrival would ignore it.
        var machine = NotchStateMachine(openTrigger: .hover)

        let changed = machine.handle(.pointerEntered)

        #expect(!changed)
        #expect(machine.state == .collapsed)
    }

    @Test("A hover that settles after the pointer left does not open the notch")
    func staleHoverSettleIsIgnored() {
        // The open-delay timer can fire after the pointer has already moved on.
        var machine = NotchStateMachine(openTrigger: .hover)
        machine.handle(.pointerEntered)
        machine.handle(.pointerExited)

        let changed = machine.handle(.hoverSettled)

        #expect(!changed)
        #expect(machine.state == .collapsed)
    }

    @Test("Pointer leaving closes the notch")
    func pointerLeavingCloses() {
        var machine = NotchStateMachine(openTrigger: .hover)
        machine.handle(.pointerEntered)
        machine.handle(.hoverSettled)

        let changed = machine.handle(.pointerExited)

        #expect(changed)
        #expect(machine.state == .collapsed)
    }

    @Test("Clicking an open notch dismisses it without moving the pointer")
    func clickDismissesWhileHovering() {
        var machine = NotchStateMachine(openTrigger: .hover)
        machine.handle(.pointerEntered)
        machine.handle(.hoverSettled)

        machine.handle(.clicked)

        #expect(machine.state == .collapsed)
    }
}

@Suite("Click behaviour")
struct ClickTriggerTests {
    @Test("Hovering does not open when the trigger is click")
    func hoverDoesNotOpen() {
        var machine = NotchStateMachine(openTrigger: .click)
        machine.handle(.pointerEntered)

        let changed = machine.handle(.hoverSettled)

        #expect(!changed)
        #expect(machine.state == .collapsed)
    }

    @Test("Clicking toggles open and closed")
    func clickToggles() {
        var machine = NotchStateMachine(openTrigger: .click)

        machine.handle(.clicked)
        #expect(machine.state == .expanded)

        machine.handle(.clicked)
        #expect(machine.state == .collapsed)
    }

    @Test("Leaving closes a notch that was opened by clicking")
    func leavingClosesAClickedNotch() {
        // Otherwise an opened panel would sit over the user's work until clicked again.
        var machine = NotchStateMachine(openTrigger: .click)
        machine.handle(.clicked)

        machine.handle(.pointerExited)

        #expect(machine.state == .collapsed)
    }
}

@Suite("Never trigger")
struct NeverTriggerTests {
    @Test("Neither hovering nor clicking opens the notch")
    func staysInert() {
        var machine = NotchStateMachine(openTrigger: .never)

        machine.handle(.pointerEntered)
        machine.handle(.hoverSettled)
        #expect(machine.state == .collapsed)

        machine.handle(.clicked)
        #expect(machine.state == .collapsed)
    }

    @Test("A peek still works when the trigger is never")
    func peeksStillHappen() {
        // `never` is about user-initiated opening; a widget announcing something is different.
        var machine = NotchStateMachine(openTrigger: .never)

        machine.handle(.peekRequested)

        #expect(machine.state == .peek)
    }
}

@Suite("Peek behaviour")
struct PeekTests {
    @Test("A peek reverts to collapsed when it expires")
    func peekReverts() {
        var machine = NotchStateMachine(openTrigger: .hover)
        machine.handle(.peekRequested)

        machine.handle(.peekExpired)

        #expect(machine.state == .collapsed)
    }

    @Test("A peek never downgrades a notch the user opened")
    func peekDoesNotDowngradeUserIntent() {
        var machine = NotchStateMachine(openTrigger: .hover)
        machine.handle(.pointerEntered)
        machine.handle(.hoverSettled)

        let changed = machine.handle(.peekRequested)

        #expect(!changed)
        #expect(machine.state == .expanded)
    }

    @Test("A peek expiring under the pointer stays open")
    func peekExpiringUnderPointerStaysOpen() {
        // Collapsing out from under a pointer that is resting on the notch would be jarring, and
        // no exit event would arrive to reopen it.
        var machine = NotchStateMachine(openTrigger: .hover)
        machine.handle(.pointerEntered)
        machine.handle(.pointerExited)
        machine.handle(.peekRequested)
        machine.handle(.pointerEntered)

        machine.handle(.peekExpired)

        #expect(machine.state == .expanded)
    }

    @Test("An expired peek collapses under the pointer when hover is not the trigger")
    func peekExpiringUnderPointerCollapsesForClickTrigger() {
        var machine = NotchStateMachine(openTrigger: .click)
        machine.handle(.peekRequested)
        machine.handle(.pointerEntered)

        machine.handle(.peekExpired)

        #expect(machine.state == .collapsed)
    }

    @Test("An expired peek is ignored once the state has moved on")
    func stalePeekExpiryIsIgnored() {
        // A peek timer that fires after the user already clicked the notch open must not close it.
        var machine = NotchStateMachine(openTrigger: .click)
        machine.handle(.peekRequested)
        machine.handle(.clicked)

        let changed = machine.handle(.peekExpired)

        #expect(!changed)
        #expect(machine.state == .expanded)
    }
}

@Suite("Change reporting")
struct ChangeReportingTests {
    @Test("Redundant events report no change")
    func redundantEventsReportNoChange() {
        // The controller skips animation work on `false`, so this has to be accurate.
        var machine = NotchStateMachine(openTrigger: .hover)
        machine.handle(.pointerEntered)
        machine.handle(.hoverSettled)

        let changed = machine.handle(.hoverSettled)

        #expect(!changed)
    }

    @Test("Exiting when already collapsed reports no change")
    func exitingWhileCollapsedReportsNoChange() {
        var machine = NotchStateMachine(openTrigger: .hover)

        let changed = machine.handle(.pointerExited)

        #expect(!changed)
    }
}
