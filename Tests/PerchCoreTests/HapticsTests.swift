import Testing

@testable import PerchCore

@Suite("Haptic policy")
struct HapticPolicyTests {

    @Test("Nothing taps by default")
    func silentByDefault() {
        let policy = HapticPolicy()

        #expect(policy.trigger == .never)
        #expect(policy.pattern(from: .collapsed, to: .expanded) == nil)
        #expect(policy.pattern(from: .collapsed, to: .peek) == nil)
    }

    @Test("`open` taps when the notch opens, and not when a widget announces")
    func openTapsOnlyOnOpening() {
        let policy = HapticPolicy(trigger: .open, pattern: .generic)

        #expect(policy.pattern(from: .collapsed, to: .expanded) == .generic)
        #expect(policy.pattern(from: .collapsed, to: .peek) == nil)
    }

    @Test("`peek` taps on an announcement, and not when the notch opens")
    func peekTapsOnlyOnAnnouncements() {
        let policy = HapticPolicy(trigger: .peek, pattern: .generic)

        #expect(policy.pattern(from: .collapsed, to: .peek) == .generic)
        #expect(policy.pattern(from: .collapsed, to: .expanded) == nil)
    }

    @Test("`all` taps for both")
    func allTapsForBoth() {
        let policy = HapticPolicy(trigger: .all, pattern: .levelChange)

        #expect(policy.pattern(from: .collapsed, to: .expanded) == .levelChange)
        #expect(policy.pattern(from: .collapsed, to: .peek) == .levelChange)
    }

    /// Closing happens as the pointer leaves.
    ///
    /// A tap there would arrive after attention has already moved on.
    @Test("Collapsing never taps, whatever it collapsed from")
    func collapsingIsSilent() {
        let policy = HapticPolicy(trigger: .all, pattern: .generic)

        #expect(policy.pattern(from: .expanded, to: .collapsed) == nil)
        #expect(policy.pattern(from: .peek, to: .collapsed) == nil)
    }

    /// An announcement the pointer is resting on becomes a real panel when it expires.
    ///
    /// That is the notch opening, and it taps as one.
    @Test("A peek settling into an open panel counts as opening")
    func peekBecomingExpandedTapsAsOpen() {
        #expect(HapticPolicy(trigger: .open).pattern(from: .peek, to: .expanded) != nil)
        #expect(HapticPolicy(trigger: .peek).pattern(from: .peek, to: .expanded) == nil)
    }

    /// The controller only calls this on a real transition, but the policy does not depend on the
    /// caller getting that right — repeated events must not stutter into repeated taps.
    @Test("A state that did not change never taps")
    func unchangedStateIsSilent() {
        let policy = HapticPolicy(trigger: .all, pattern: .generic)

        for state in [NotchState.collapsed, .peek, .expanded] {
            #expect(policy.pattern(from: state, to: state) == nil)
        }
    }
}

@Suite("Haptic configuration")
struct HapticConfigTests {

    @Test("Both keys parse and reach the policy")
    func parsesKeys() {
        let result = ConfigLoader.load(
            source: """
                haptics = all
                haptic-pattern = level-change
                """
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.config.hapticPolicy == HapticPolicy(trigger: .all, pattern: .levelChange))
    }

    @Test("A bad value is reported and skipped, leaving the default in place")
    func rejectsUnknownValues() {
        let result = ConfigLoader.load(source: "haptics = buzz")

        #expect(result.config.haptics == .never)
        #expect(result.diagnostics.count == 1)
        // The message lists what was accepted rather than only what was wrong — the reader is
        // someone editing a text file.
        #expect(result.diagnostics.first?.message.contains("never, open, peek, all") == true)
    }

    @Test("An empty value restores the default")
    func emptyValueResets() {
        let result = ConfigLoader.load(
            source: """
                haptics = all
                haptics =
                """
        )

        #expect(result.config.haptics == .never)
    }

    @Test("Every pattern spelling in the schema round-trips through the parser")
    func patternSpellingsRoundTrip() {
        for pattern in HapticPattern.allCases {
            let result = ConfigLoader.load(source: "haptic-pattern = \(pattern.rawValue)")

            #expect(result.diagnostics.isEmpty, "\(pattern.rawValue) was rejected")
            #expect(result.config.hapticPattern == pattern)
        }
    }
}
