import Testing

@testable import PerchSystem

@Suite("Volume state")
struct VolumeStateTests {

    private func state(_ level: Double, muted: Bool = false) -> VolumeState {
        VolumeState(level: level, isMuted: muted, deviceName: "Test Output")
    }

    @Test("Levels are clamped to what can be drawn")
    func levelsAreClamped() {
        // A device can report slightly outside 0...1, and the widget draws this straight into a
        // bar width — an unclamped 1.02 draws past the panel.
        #expect(state(1.4).level == 1)
        #expect(state(-0.2).level == 0)
        #expect(state(0.5).level == 0.5)
    }

    @Test("Muting is not the same as zero")
    func mutingKeepsTheLevel() {
        // What unmuting restores. A HUD that showed a muted device as 0% would be lying about
        // where the volume is about to come back to.
        let muted = state(0.6, muted: true)

        #expect(muted.level == 0.6)
        #expect(muted.effectiveLevel == 0)
    }

    @Test("The first reading is never an announcement")
    func firstReadingIsNotAnnouncable() {
        // The source emits once on start so a subscriber knows where things stand. Announcing that
        // would pop the notch open every time the widget activates — on launch, on every config
        // save, and every time the display wakes.
        #expect(state(0.5).isAnnouncable(comparedTo: nil) == false)
    }

    @Test("An unchanged level is not an announcement")
    func identicalLevelIsNotAnnouncable() {
        #expect(state(0.5).isAnnouncable(comparedTo: state(0.5)) == false)
    }

    @Test("A change too small to draw is not an announcement")
    func imperceptibleChangeIsNotAnnouncable() {
        // CoreAudio reports a float and the hardware keys move in fine steps. Two values differing
        // below what a bar could show are not a change anyone made.
        #expect(state(0.5000).isAnnouncable(comparedTo: state(0.5001)) == false)
    }

    @Test("A real change is an announcement")
    func realChangeIsAnnouncable() {
        #expect(state(0.5).isAnnouncable(comparedTo: state(0.6)))
    }

    @Test("Muting and unmuting each announce, at the same level")
    func muteChangesAnnounce() {
        // The level does not move when you press the mute key, so comparing only levels would miss
        // it entirely — the most obviously wrong thing a volume HUD could do.
        #expect(state(0.5, muted: true).isAnnouncable(comparedTo: state(0.5, muted: false)))
        #expect(state(0.5, muted: false).isAnnouncable(comparedTo: state(0.5, muted: true)))
    }
}
