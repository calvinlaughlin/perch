import Foundation

/// A calendar's colour, as components rather than as a `CGColor`.
///
/// `CGColor` is not `Sendable` and drags CoreGraphics into everything that touches an event, so the
/// colour crosses this boundary as three numbers and becomes a `Color` on the far side. It is the
/// only way to tell work from personal at a glance, which is worth carrying.
public struct EventColor: Equatable, Sendable {

    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// One event, as the notch needs to draw it.
///
/// A flattened value rather than an `EKEvent`: the widget never touches EventKit, which is what
/// lets every rule about what is next, what is worth announcing, and when to wake up next be tested
/// without a calendar, a permission, or a display.
public struct CalendarEvent: Equatable, Sendable, Identifiable {

    /// The calendar item this came from.
    ///
    /// Shared by every occurrence of a recurring event, which is exactly why it is not the identity
    /// — see ``id``. Kept because it is what addresses the event in Calendar.app.
    public let itemIdentifier: String

    public let title: String
    public let start: Date
    public let end: Date

    /// Whether the event occupies whole days rather than a span of clock time.
    public let isAllDay: Bool

    /// Whether you have said no to this.
    public let isDeclined: Bool

    /// Whether the organiser has called it off.
    public let isCancelled: Bool

    /// The calendar it came from, e.g. `Work`.
    public let calendarName: String

    /// That calendar's colour, when it has one.
    public let color: EventColor?

    /// Where it is, which for most meetings is a URL rather than a room.
    public let location: String?

    /// Somewhere to join, when the event carries one.
    ///
    /// Resolved once, on the way in — see ``MeetingLink``. Doing it here rather than at draw time
    /// means the scan over notes and location happens per event rather than per repaint.
    public let joinURL: URL?

    /// Stable identity for one *occurrence*.
    ///
    /// Not the calendar item's identifier alone: every occurrence of a recurring event shares that,
    /// so a weekly standup would be announced once and then never again. The start date is what
    /// separates this Tuesday's from next Tuesday's.
    public var id: String {
        "\(itemIdentifier)|\(start.timeIntervalSince1970)"
    }

    public init(
        itemIdentifier: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        isDeclined: Bool = false,
        isCancelled: Bool = false,
        calendarName: String = "",
        color: EventColor? = nil,
        location: String? = nil,
        joinURL: URL? = nil
    ) {
        self.itemIdentifier = itemIdentifier
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isDeclined = isDeclined
        self.isCancelled = isCancelled
        self.calendarName = calendarName
        self.color = color
        self.location = location
        self.joinURL = joinURL
    }

    /// The moment this stops being worth showing.
    ///
    /// Floored a minute past the start rather than taken as written. Invitations do produce
    /// zero-length events, and one of those would otherwise disappear at exactly the instant it
    /// began — which is the one moment it mattered.
    public var displayEnd: Date {
        max(end, start.addingTimeInterval(60))
    }

    /// Whether the event is happening right now.
    public func isUnderway(at now: Date) -> Bool {
        start <= now && now < displayEnd
    }
}
