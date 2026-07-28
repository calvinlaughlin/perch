import AppKit
import PerchCore
import Testing

@testable import PerchUI

@Suite("Haptic engine")
@MainActor
struct HapticEngineTests {

    /// Records what was asked for, since the tap itself leaves no trace software can read.
    private final class Recorder {
        var patterns: [HapticPattern] = []
    }

    private func engine(_ recorder: Recorder) -> HapticEngine {
        HapticEngine { recorder.patterns.append($0) }
    }

    @Test("A transition the policy allows reaches the performer once")
    func performsAllowedTransition() {
        let recorder = Recorder()

        engine(recorder).perform(
            HapticPolicy(trigger: .open, pattern: .generic), from: .collapsed, to: .expanded)

        #expect(recorder.patterns == [.generic])
    }

    @Test("A transition the policy declines never reaches the performer")
    func skipsDeclinedTransition() {
        let recorder = Recorder()
        let engine = engine(recorder)

        engine.perform(HapticPolicy(), from: .collapsed, to: .expanded)
        engine.perform(
            HapticPolicy(trigger: .open), from: .expanded, to: .collapsed)

        #expect(recorder.patterns.isEmpty)
    }

    /// The mapping is the one place a wrong answer would be silent — every pattern is a valid tap,
    /// so picking the wrong one feels like *something* and passes every other check.
    @Test("Each configured pattern maps to the AppKit pattern of the same name")
    func mapsPatternsToAppKit() {
        #expect(HapticPattern.generic.patternType == .generic)
        #expect(HapticPattern.alignment.patternType == .alignment)
        #expect(HapticPattern.levelChange.patternType == .levelChange)
    }

    @Test("The three configured patterns are distinct AppKit patterns")
    func patternsAreDistinct() {
        let mapped = Set(HapticPattern.allCases.map(\.patternType.rawValue))

        #expect(mapped.count == HapticPattern.allCases.count)
    }
}
