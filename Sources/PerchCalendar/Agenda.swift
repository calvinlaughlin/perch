import Foundation

/// What is left of today, and when to look again.
///
/// Every rule the calendar widget has about what to show and when to wake up lives here as a pure
/// function over a list of events and a `now` that is passed in rather than read. That is what makes
/// the awkward parts — a declined invitation, an all-day event that is not "next", a countdown
/// crossing midnight — testable at any hour of any day, without a calendar or a permission.
public enum Agenda {

    /// What is left of today, in the order it should be drawn.
    ///
    /// The horizon is the end of today and nothing beyond it. Tomorrow's nine o'clock pinned to the
    /// bezel all evening is not information you can act on, and an agenda that quietly becomes
    /// tomorrow's is one you stop trusting to be today's.
    ///
    /// All-day events sort first. They have no time to be next *at*, so they read as a heading over
    /// the day rather than as another appointment among the timed ones.
    public static func upcoming(
        from events: [CalendarEvent],
        at now: Date,
        calendar: Calendar = .current
    ) -> [CalendarEvent] {
        let today = calendar.startOfDay(for: now)
        let tomorrow =
            calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86400)

        return
            events
            .filter { event in
                // A cancelled event, or one you declined, is not an appointment. Counting down at
                // someone toward a meeting they have already said no to is worse than showing them
                // nothing — and this is filtered here, rather than on the way out of EventKit, so
                // that it is a rule a test can hold rather than a line nobody can reach.
                guard !event.isDeclined, !event.isCancelled else { return false }
                guard event.start < tomorrow else { return false }
                // An all-day event is "left today" for the whole day, including the part of it that
                // has already happened: it is a fact about the day rather than a moment in it.
                guard !event.isAllDay else { return event.end > today }
                return event.displayEnd > now
            }
            .sorted { first, second in
                if first.isAllDay != second.isAllDay { return first.isAllDay }
                if first.start != second.start { return first.start < second.start }
                return first.title < second.title
            }
    }

    /// The event the strip shows and the countdown counts down to.
    ///
    /// The first timed event that has not ended — so a meeting you are *in* stays the focus until it
    /// is over, rather than being replaced by the next one the moment it starts. Mid-meeting, what
    /// you glance up for is how long is left of this, not what comes after it.
    ///
    /// - Parameters:
    ///   - events: the result of ``upcoming(from:at:calendar:)``.
    ///   - now: the moment to judge against.
    /// - Returns: the event to count down to, or nil when the day has nothing left in it.
    public static func focus(in events: [CalendarEvent], at now: Date) -> CalendarEvent? {
        events.first { !$0.isAllDay && $0.displayEnd > now }
    }

    /// Every event currently due an announcement, soonest first.
    ///
    /// Only events that have not started. Announcing one already underway is telling someone they
    /// are late, which is both useless and unkind, and it is what a naive "within five minutes"
    /// window does for the first five minutes of every meeting.
    ///
    /// All of them rather than just the soonest, because the caller is the one that knows what it
    /// has already said. Returning only the first means back-to-back meetings that fall inside the
    /// lead together announce once between them: the second stays hidden behind the first until the
    /// first *starts*, by which time its own warning is most of the way gone.
    ///
    /// - Parameters:
    ///   - events: the result of ``upcoming(from:at:calendar:)``.
    ///   - now: the moment to judge against.
    ///   - lead: how far ahead to announce.
    /// - Returns: the events due an announcement, soonest first, or empty when none are.
    public static func alertable(
        in events: [CalendarEvent],
        at now: Date,
        lead: TimeInterval
    ) -> [CalendarEvent] {
        events.filter { event in
            guard !event.isAllDay, event.start > now else { return false }
            return event.start.timeIntervalSince(now) <= lead
        }
    }

    /// The rows to draw when there is only room for so many.
    ///
    /// Not simply the first `limit` of them. All-day events sort first, so a day carrying three
    /// birthdays from a subscribed calendar would fill a three-row card with things you do not have
    /// to be anywhere for, and push the meeting that starts in ten minutes off the bottom.
    ///
    /// So at least one slot is always kept for a timed event when there is one. The all-day events
    /// give up the room, because they are the ones with nowhere to be.
    ///
    /// - Parameters:
    ///   - events: the result of ``upcoming(from:at:calendar:)``.
    ///   - limit: how many rows there is room for.
    /// - Returns: the events to draw, in the same order, at most `limit` of them.
    public static func rows(from events: [CalendarEvent], limit: Int) -> [CalendarEvent] {
        guard limit > 0 else { return [] }
        guard events.count > limit else { return events }

        let timed = events.filter { !$0.isAllDay }
        guard !timed.isEmpty else { return Array(events.prefix(limit)) }

        let allDay = events.filter(\.isAllDay)
        let allDaySlots = min(allDay.count, limit - 1)

        return Array(allDay.prefix(allDaySlots)) + Array(timed.prefix(limit - allDaySlots))
    }

    /// The next moment anything on screen would change.
    ///
    /// The widget sleeps to this instead of ticking. A calendar changes a handful of times a day and
    /// a clock changes sixty times an hour, so a per-second timer would spend all day waking up to
    /// redraw the same three rows — and this widget promises to cost nothing behind a closed notch.
    ///
    /// - Parameters:
    ///   - now: the moment to schedule from.
    ///   - events: the result of ``upcoming(from:at:calendar:)``.
    ///   - lead: the announcement lead, or nil when announcements are off.
    ///   - showsCountdown: whether a countdown is currently drawn. False behind a closed notch,
    ///     where the minute boundaries are of no interest to anyone and only the announcement is.
    ///   - calendar: the calendar the day boundary is taken from.
    /// - Returns: the next instant worth waking for, always later than `after`.
    public static func nextWake(
        after now: Date,
        events: [CalendarEvent],
        lead: TimeInterval?,
        showsCountdown: Bool,
        calendar: Calendar = .current
    ) -> Date {
        let today = calendar.startOfDay(for: now)
        let tomorrow =
            calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86400)

        // Midnight is always a candidate: the horizon moves, and "Nothing left today" has to stop
        // being true at some point even on a day when nothing else happens.
        var candidates: [Date] = [tomorrow]

        for event in events {
            candidates.append(event.start)
            candidates.append(event.displayEnd)
            if let lead { candidates.append(event.start.addingTimeInterval(-lead)) }

            // The moment a countdown starts being drawn at all. Without this the widget sleeps
            // straight past it: nothing else changes an hour before a meeting, so the row would go
            // on showing a clock time until the meeting itself arrived to wake it.
            if showsCountdown, !event.isAllDay {
                candidates.append(event.start.addingTimeInterval(-EventPhrase.countdownWindow))
            }
        }

        // A minute boundary matters only while a countdown is being drawn, and only while one is
        // close enough to be counting. Every other second of the hour redraws nothing.
        let isCounting = events.contains { event in
            guard !event.isAllDay, event.start > now else { return false }
            return event.start.timeIntervalSince(now) <= EventPhrase.countdownWindow
        }
        if showsCountdown, isCounting {
            candidates.append(nextMinute(after: now))
        }

        let next = candidates.filter { $0 > now }.min() ?? tomorrow

        // Never schedule for the instant we are already at. Rounding, or an event starting exactly
        // now, would otherwise produce a task that wakes, finds nothing changed, and schedules
        // itself again — a spin loop dressed as a timer.
        return max(next, now.addingTimeInterval(1))
    }

    /// The start of the next whole minute.
    private static func nextMinute(after now: Date) -> Date {
        let seconds = now.timeIntervalSince1970
        return Date(timeIntervalSince1970: (seconds / 60).rounded(.down) * 60 + 60)
    }
}
