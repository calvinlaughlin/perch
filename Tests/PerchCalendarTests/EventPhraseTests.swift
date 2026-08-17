import Foundation
import Testing

@testable import PerchCalendar

/// How long until something, in words.
///
/// Small enough to look obvious and wrong in three different ways if nobody writes the cases down:
/// which way it rounds, when it gives up, and what it says once the moment has passed.
@Suite("Event phrasing")
struct EventPhraseTests {

    private let now = Clock.at(9, 55)

    @Test("A countdown rounds up")
    func countdownRoundsUp() {
        // Rounding down would say "in 4m" for four minutes and fifty-nine seconds, and would spend
        // the last minute before every meeting saying "in 0m".
        #expect(EventPhrase.countdown(to: Clock.at(10), at: now) == "in 5m")
        #expect(EventPhrase.countdown(to: Clock.at(10).addingTimeInterval(-1), at: now) == "in 5m")
        #expect(EventPhrase.countdown(to: now.addingTimeInterval(1), at: now) == "in 1m")
    }

    @Test("Something that has started is now")
    func startedEventsReadAsNow() {
        #expect(EventPhrase.countdown(to: now, at: now) == "now")
        #expect(EventPhrase.countdown(to: Clock.at(9, 30), at: now) == "now")
    }

    @Test("Past an hour there is nothing worth counting down")
    func distantEventsHaveNoCountdown() {
        // `in 3h` is not a countdown, it is the time written badly — so the caller falls back to
        // the clock time, which says more.
        #expect(EventPhrase.countdown(to: Clock.at(11), at: now) == nil)
        #expect(EventPhrase.countdown(to: now.addingTimeInterval(3600), at: now) == "in 60m")
        #expect(EventPhrase.countdown(to: now.addingTimeInterval(3601), at: now) == nil)
    }

    @Test("An announcement is spelled out, and counts one minute singular")
    func announcementsAreLegibleAcrossADesk() {
        #expect(EventPhrase.announcement(to: Clock.at(10), at: now) == "in 5 min")
        #expect(EventPhrase.announcement(to: Clock.at(9, 56), at: now) == "in 1 min")
        #expect(EventPhrase.announcement(to: now, at: now) == "starting now")
    }
}
