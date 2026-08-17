import Foundation
import Testing

@testable import PerchCalendar

/// A fixed day in a fixed zone, so "what is left of today" means the same thing on every machine
/// that runs these and at every hour they are run.
enum Clock {

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// A moment on the reference day, 10 March 2026.
    static func at(_ hour: Int, _ minute: Int = 0) -> Date {
        let components = DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: 2026, month: 3, day: 10, hour: hour, minute: minute)
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    /// The same, a day later.
    static func tomorrow(_ hour: Int, _ minute: Int = 0) -> Date {
        at(hour, minute).addingTimeInterval(86400)
    }

    static let midnight = tomorrow(0)
}

func event(
    _ title: String,
    from start: Date,
    to end: Date,
    allDay: Bool = false,
    declined: Bool = false,
    cancelled: Bool = false
) -> CalendarEvent {
    CalendarEvent(
        itemIdentifier: title,
        title: title,
        start: start,
        end: end,
        isAllDay: allDay,
        isDeclined: declined,
        isCancelled: cancelled
    )
}

@Suite("Agenda")
struct AgendaTests {

    private func upcoming(_ events: [CalendarEvent], at now: Date) -> [CalendarEvent] {
        Agenda.upcoming(from: events, at: now, calendar: Clock.calendar)
    }

    // MARK: - What is left of today

    @Test("An event that has ended is not left")
    func endedEventsAreGone() {
        let events = [
            event("Standup", from: Clock.at(9), to: Clock.at(9, 15)),
            event("Review", from: Clock.at(14), to: Clock.at(15)),
        ]

        let left = upcoming(events, at: Clock.at(10))

        #expect(left.map(\.title) == ["Review"])
    }

    @Test("A meeting you are in is still left")
    func underwayEventsRemain() {
        // The one you are *in* is the one you look up to check the time of. Dropping it the moment
        // it starts means the panel is wrong for exactly as long as the meeting lasts.
        let events = [event("Review", from: Clock.at(14), to: Clock.at(15))]

        let left = upcoming(events, at: Clock.at(14, 30))

        #expect(left.map(\.title) == ["Review"])
    }

    @Test("Tomorrow is not today")
    func tomorrowIsExcluded() {
        // The horizon is the end of today, deliberately. Tomorrow's first meeting pinned to the
        // bezel all evening is not something you can act on.
        let events = [
            event("Tomorrow's standup", from: Clock.tomorrow(9), to: Clock.tomorrow(9, 15))
        ]

        #expect(upcoming(events, at: Clock.at(19)).isEmpty)
    }

    @Test("A zero-length event does not vanish at the instant it begins")
    func zeroLengthEventsSurvive() {
        // Invitations do produce these. Taking the end date at face value would drop it at exactly
        // the moment it mattered.
        let events = [event("Ping", from: Clock.at(12), to: Clock.at(12))]

        #expect(upcoming(events, at: Clock.at(12)).count == 1)
        #expect(upcoming(events, at: Clock.at(12, 2)).isEmpty)
    }

    @Test("A declined invitation is not an appointment")
    func declinedEventsAreGone() {
        let events = [
            event("Optional sync", from: Clock.at(14), to: Clock.at(15), declined: true),
            event("Review", from: Clock.at(16), to: Clock.at(17)),
        ]

        #expect(upcoming(events, at: Clock.at(10)).map(\.title) == ["Review"])
    }

    @Test("A cancelled event is not an appointment either")
    func cancelledEventsAreGone() {
        let events = [event("Called off", from: Clock.at(14), to: Clock.at(15), cancelled: true)]

        #expect(upcoming(events, at: Clock.at(10)).isEmpty)
    }

    @Test("All-day events head the list and stay there all day")
    func allDayEventsSortFirst() {
        let allDay = event(
            "Conference", from: Clock.at(0), to: Clock.midnight, allDay: true)
        let meeting = event("Review", from: Clock.at(14), to: Clock.at(15))

        let left = upcoming([meeting, allDay], at: Clock.at(13))

        #expect(left.map(\.title) == ["Conference", "Review"])
    }

    @Test("Simultaneous events keep a stable order")
    func tiesAreBrokenPredictably() {
        // Two events at the same minute is ordinary, and an order that changes between repaints is
        // a panel whose rows swap under the pointer.
        let first = event("Alpha", from: Clock.at(14), to: Clock.at(15))
        let second = event("Beta", from: Clock.at(14), to: Clock.at(15))

        #expect(upcoming([second, first], at: Clock.at(10)).map(\.title) == ["Alpha", "Beta"])
    }

    // MARK: - The focus

    @Test("The focus is the meeting you are in, not the one after it")
    func focusPrefersTheUnderwayEvent() {
        let events = upcoming(
            [
                event("Review", from: Clock.at(14), to: Clock.at(15)),
                event("1:1", from: Clock.at(15), to: Clock.at(15, 30)),
            ], at: Clock.at(14, 30))

        #expect(Agenda.focus(in: events, at: Clock.at(14, 30))?.title == "Review")
    }

    @Test("An all-day event is never the focus")
    func focusSkipsAllDayEvents() {
        // There is no moment to count down to, and a conference occupying the countdown for eight
        // hours is the countdown saying nothing all day.
        let events = upcoming(
            [
                event("Conference", from: Clock.at(0), to: Clock.midnight, allDay: true),
                event("Review", from: Clock.at(14), to: Clock.at(15)),
            ], at: Clock.at(10))

        #expect(Agenda.focus(in: events, at: Clock.at(10))?.title == "Review")
    }

    @Test("Nothing left means no focus")
    func focusIsNilWhenTheDayIsDone() {
        #expect(Agenda.focus(in: [], at: Clock.at(19)) == nil)
    }

    // MARK: - What fits

    @Test("A short card keeps the meeting, not the birthdays")
    func rowsKeepATimedEvent() {
        // The failure this exists to prevent: three all-day events sort first, fill a three-row
        // card, and push the thing you actually have to be at in ten minutes off the bottom.
        let events = upcoming(
            [
                event("Ada's birthday", from: Clock.at(0), to: Clock.midnight, allDay: true),
                event("Grace's birthday", from: Clock.at(0), to: Clock.midnight, allDay: true),
                event("Katherine's birthday", from: Clock.at(0), to: Clock.midnight, allDay: true),
                event("Standup", from: Clock.at(14), to: Clock.at(14, 30)),
            ], at: Clock.at(13))

        let rows = Agenda.rows(from: events, limit: 3)

        #expect(rows.count == 3)
        #expect(rows.last?.title == "Standup")
    }

    @Test("With room to spare nothing is dropped or reordered")
    func rowsAreUntouchedWhenTheyFit() {
        let events = upcoming(
            [
                event("Conference", from: Clock.at(0), to: Clock.midnight, allDay: true),
                event("Standup", from: Clock.at(14), to: Clock.at(14, 30)),
            ], at: Clock.at(13))

        #expect(Agenda.rows(from: events, limit: 3).map(\.title) == ["Conference", "Standup"])
    }

    @Test("A day of nothing but all-day events still fills the card")
    func rowsFallBackToAllDayEvents() {
        // The reservation is for a timed event that exists. With none, holding a slot empty would
        // be leaving a gap in the name of something that was never coming.
        let events = upcoming(
            [
                event("Ada's birthday", from: Clock.at(0), to: Clock.midnight, allDay: true),
                event("Grace's birthday", from: Clock.at(0), to: Clock.midnight, allDay: true),
            ], at: Clock.at(13))

        #expect(Agenda.rows(from: events, limit: 1).count == 1)
    }

    // MARK: - Announcements

    @Test("An event inside the lead is worth announcing")
    func alertsFireInsideTheLead() {
        let events = upcoming(
            [event("Standup", from: Clock.at(10), to: Clock.at(10, 15))], at: Clock.at(9, 56))

        #expect(
            Agenda.alertable(in: events, at: Clock.at(9, 56), lead: 300).map(\.title) == ["Standup"]
        )
    }

    @Test("An event beyond the lead is not")
    func alertsWaitOutsideTheLead() {
        let events = upcoming(
            [event("Standup", from: Clock.at(10), to: Clock.at(10, 15))], at: Clock.at(9, 50))

        #expect(Agenda.alertable(in: events, at: Clock.at(9, 50), lead: 300).isEmpty)
    }

    @Test("A meeting already under way is never announced")
    func alertsNeverChaseAStartedMeeting() {
        // The failure mode of a naive "within five minutes" window: it announces for the first five
        // minutes of every meeting, which is telling someone they are late.
        let events = upcoming(
            [event("Standup", from: Clock.at(10), to: Clock.at(10, 15))], at: Clock.at(10, 2))

        #expect(Agenda.alertable(in: events, at: Clock.at(10, 2), lead: 300).isEmpty)
    }

    @Test("An all-day event is never announced")
    func allDayEventsAreNotAnnounced() {
        let events = upcoming(
            [event("Conference", from: Clock.at(0), to: Clock.midnight, allDay: true)],
            at: Clock.at(0))

        #expect(Agenda.alertable(in: events, at: Clock.at(0), lead: 300).isEmpty)
    }

    // MARK: - When to wake up

    private func wake(
        _ events: [CalendarEvent],
        at now: Date,
        lead: TimeInterval? = 300,
        showsCountdown: Bool = true
    ) -> Date {
        Agenda.nextWake(
            after: now,
            events: upcoming(events, at: now),
            lead: lead,
            showsCountdown: showsCountdown,
            calendar: Clock.calendar
        )
    }

    @Test("With nothing on, it sleeps until the day rolls over")
    func emptyDaySleepsUntilMidnight() {
        #expect(wake([], at: Clock.at(19)) == Clock.midnight)
    }

    @Test("It wakes for the announcement rather than after it")
    func wakesAtTheAlertInstant() {
        // The whole point of the schedule. Waking a minute late means announcing a four-minute
        // warning, which is a different promise than the one in the config file.
        let standup = event("Standup", from: Clock.at(14), to: Clock.at(14, 30))

        let hidden = wake([standup], at: Clock.at(11), showsCountdown: false)

        #expect(hidden == Clock.at(13, 55))
    }

    @Test("Behind a closed notch it ignores the minutes")
    func hiddenWakesSkipMinuteBoundaries() {
        // A countdown nobody can see is not worth waking sixty times an hour to redraw. This is the
        // difference between the promise `runsWhileHidden` makes and a per-minute timer.
        let standup = event("Standup", from: Clock.at(14), to: Clock.at(14, 30))

        let hidden = wake([standup], at: Clock.at(13, 57), showsCountdown: false)

        #expect(hidden == Clock.at(14))
    }

    @Test("On screen inside the hour it wakes on the minute")
    func visibleWakesOnTheMinute() {
        let standup = event("Standup", from: Clock.at(14), to: Clock.at(14, 30))
        let now = Clock.at(13, 30).addingTimeInterval(20)

        #expect(wake([standup], at: now) == Clock.at(13, 31))
    }

    @Test("On screen it wakes when the countdown is due to begin")
    func visibleWakesWhenTheCountdownStarts() {
        // Nothing else changes an hour before a meeting. Without this candidate the widget sleeps
        // straight past the moment the countdown was supposed to appear, and the row goes on
        // showing a clock time until the meeting itself wakes it.
        let standup = event("Standup", from: Clock.at(17), to: Clock.at(17, 30))
        let now = Clock.at(13, 30).addingTimeInterval(20)

        #expect(wake([standup], at: now, lead: nil) == Clock.at(16))
    }

    @Test("It never schedules for a moment that has already arrived")
    func wakeIsAlwaysInTheFuture() {
        // An event starting exactly now would otherwise produce a task that wakes, finds nothing
        // changed, and immediately schedules itself again: a spin loop dressed as a timer.
        let now = Clock.at(14)
        let starting = event("Standup", from: now, to: Clock.at(14, 30))

        #expect(wake([starting], at: now) > now)
    }
}
