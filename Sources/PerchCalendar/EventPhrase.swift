import Foundation

/// How long until something, in words.
///
/// Separate from the widget because it is where the arguable decisions live — when a countdown
/// starts, when it gives up, and whether 4m59s is four minutes or five — and those are worth
/// writing tests against rather than eyeballing at the top of the hour.
public enum EventPhrase {

    /// How far ahead a countdown is worth showing at all.
    ///
    /// An hour. Past that the clock time says more: `in 47m` is a countdown, `in 3h` is just the
    /// time written badly.
    public static let countdownWindow: TimeInterval = 3600

    /// The countdown to a moment, or nil when it is too far off to count down to.
    ///
    /// Rounded **up**, which is how a countdown is read: it says `in 1m` right up until the thing
    /// starts, rather than saying `now` for the last fifty-nine seconds of not-yet.
    public static func countdown(to date: Date, at now: Date) -> String? {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "now" }
        guard seconds <= countdownWindow else { return nil }

        return "in \(Int((seconds / 60).rounded(.up)))m"
    }

    /// The same span spelled out, for an announcement.
    ///
    /// A peek is read at a glance from across a desk, where `in 5m` is a smaller target than
    /// `in 5 min`. Only ever a handful of minutes, so there is no hour case to get wrong.
    public static func announcement(to date: Date, at now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "starting now" }

        let minutes = Int((seconds / 60).rounded(.up))
        return minutes == 1 ? "in 1 min" : "in \(minutes) min"
    }
}
