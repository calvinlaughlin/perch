import Foundation

/// Whether perch is allowed to read the calendar.
///
/// Three states rather than two: before the question has been asked there is nothing to say, and a
/// widget that draws "no access" during the moment between opening and the system answering is a
/// widget that accuses the user of something they have not done.
public enum CalendarAccess: Equatable, Sendable {

    /// Not asked yet, or asked and not yet answered.
    case unknown

    /// Allowed to read events.
    case granted

    /// Refused, or restricted by policy. Nothing will arrive.
    case denied
}

/// Everything a source knows, in one value.
///
/// The access state travels with the events rather than beside them so the widget cannot render a
/// stale permission against a fresh list, or an empty list against a permission that has since been
/// revoked in System Settings.
public struct CalendarFeed: Equatable, Sendable {

    public var access: CalendarAccess

    /// Events in the queried window, unfiltered and in no particular order.
    ///
    /// Deliberately raw: which of these is next, which are worth drawing, and which have been
    /// declined is ``Agenda``'s business, and putting it here would put it somewhere it cannot be
    /// tested without a calendar.
    public var events: [CalendarEvent]

    public init(access: CalendarAccess, events: [CalendarEvent] = []) {
        self.access = access
        self.events = events
    }
}

/// Somewhere calendar events come from.
///
/// A protocol for the same reason ``MediaSource`` and ``VolumeSource`` are: it is the seam that
/// keeps EventKit out of the widget. Everything downstream of here can be tested with a fake, at
/// any date, with no permission granted and no events in the tester's own calendar.
public protocol EventSource: AnyObject, Sendable {

    /// Feeds as access is decided and as the calendar changes.
    ///
    /// Emits once access has been settled, and again whenever the system reports a change. The
    /// sequence finishes when the source stops.
    var updates: AsyncStream<CalendarFeed> { get }

    /// Begin producing feeds, asking for access if it has not been asked for yet.
    ///
    /// Calling twice is a no-op.
    func start()

    /// Stop and release everything: observers, queries, the store. Calling twice is a no-op.
    func stop()

    /// Re-query the calendar.
    ///
    /// For the one thing a change notification cannot cover: the window itself moving. The query
    /// runs from today, so at midnight the answer is stale even though nothing was edited.
    func refresh()
}
