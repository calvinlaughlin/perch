import Testing

@testable import PerchCore

@Suite("Tapping when a card turns")
struct CardTurnHapticsTests {

    @Test(
        "Turning a card taps whenever haptics are on at all",
        arguments: [
            HapticTrigger.open, .peek, .all,
        ])
    func tapsWheneverEnabled(trigger: HapticTrigger) {
        // Not gated on `open` or `peek`. Those are notifications, and whether you want to be
        // notified is a taste. A card turning under your own fingers is feedback for a movement you
        // are in the middle of making, so it follows the one question already answered: are haptics
        // on at all.
        let policy = HapticPolicy(trigger: trigger, pattern: .generic)
        #expect(policy.patternForCardTurn() != nil)
    }

    @Test("Haptics off means no tap")
    func silentWhenOff() {
        #expect(HapticPolicy(trigger: .never, pattern: .generic).patternForCardTurn() == nil)
    }

    @Test("A card turn is always a level change, whatever the configured pattern")
    func alwaysLevelChange() {
        // `levelChange` is the two-part tap of a detent moving between stops, which is what a card
        // reaching the next stop on a spindle is. Honouring the configured pattern here would let
        // "announce with a firm tap" become a firm tap per card, which is nobody's intent.
        for pattern in HapticPattern.allCases {
            let policy = HapticPolicy(trigger: .all, pattern: pattern)
            #expect(policy.patternForCardTurn() == .levelChange)
        }
    }

    @Test("Turning a card does not disturb the state-change taps")
    func leavesTransitionsAlone() {
        let policy = HapticPolicy(trigger: .peek, pattern: .alignment)
        #expect(policy.pattern(from: .collapsed, to: .expanded) == nil)
        #expect(policy.pattern(from: .collapsed, to: .peek) == .alignment)
    }
}
