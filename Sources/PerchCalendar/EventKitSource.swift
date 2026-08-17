import CoreGraphics
import EventKit
import Foundation
import PerchCore

/// Reads events from the system calendar.
///
/// Read-only, and local: perch asks EventKit what is on today and draws it. Nothing is written, and
/// nothing leaves the machine.
///
/// Every touch of the store happens on one serial queue, off the main thread. `events(matching:)` is
/// synchronous and talks to another process, so on the main thread it is a stall in the middle of
/// the panel's animation — and the notification EventKit posts on a change arrives on a thread of
/// its choosing, so the queue is also what keeps two queries from overlapping.
public final class EventKitSource: EventSource, @unchecked Sendable {

    public let updates: AsyncStream<CalendarFeed>
    private let continuation: AsyncStream<CalendarFeed>.Continuation

    private let store = EKEventStore()
    private let queue = DispatchQueue(label: "dev.perch.perch.calendar")

    /// Guards `isRunning` and `observer` against the callbacks EventKit makes on its own threads.
    private let lock = NSLock()
    private var isRunning = false
    private var observer: NSObjectProtocol?
    private var isRefreshPending = false

    /// Calendar titles to read, lowercased.
    ///
    /// Empty means all of them.
    private let included: Set<String>

    /// Whether the missing-calendar warning has already been said.
    ///
    /// Said once rather than on every refresh: a typo in a config file is one mistake, not one per
    /// calendar change for the rest of the session.
    private var hasReportedUnmatched = false

    /// The last access state said out loud, so a grant or a refusal is logged once and not per
    /// query.
    private var reported: CalendarAccess = .unknown

    public init(including calendars: Set<String> = []) {
        included = Set(calendars.map { $0.lowercased() })
        (updates, continuation) = AsyncStream.makeStream(of: CalendarFeed.self)
    }

    deinit { stop() }

    public func start() {
        lock.lock()
        guard !isRunning else { return lock.unlock() }
        isRunning = true
        lock.unlock()

        // Registered before access is settled, deliberately. Granting the permission in System
        // Settings is itself a change, so this is what makes a grant land without a relaunch.
        let token = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: nil
        ) { [weak self] _ in
            self?.refresh()
        }

        lock.lock()
        observer = token
        lock.unlock()

        authorize()
    }

    public func stop() {
        lock.lock()
        guard isRunning else { return lock.unlock() }
        isRunning = false
        let token = observer
        observer = nil
        lock.unlock()

        if let token { NotificationCenter.default.removeObserver(token) }
        continuation.finish()
    }

    public func refresh() {
        guard running, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }

        // Coalesced rather than run per notification. A calendar sync posts a burst of changes —
        // one per account, sometimes one per event — and a query plus a redraw for each of them is
        // a panel that flickers through a dozen identical states to arrive where it started.
        lock.lock()
        guard !isRefreshPending else { return lock.unlock() }
        isRefreshPending = true
        lock.unlock()

        queue.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.isRefreshPending = false
            self.lock.unlock()
            self.query()
        }
    }

    private var running: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRunning
    }

    // MARK: - Access

    /// Settle whether perch may read the calendar, asking if it has not been asked before.
    ///
    /// Being refused is an ordinary outcome rather than a failure, the same way the volume HUD
    /// treats a missing Accessibility grant: perch says what it needs and where to give it, and
    /// carries on running.
    private func authorize() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            query()

        case .denied, .restricted:
            report(.denied)
            emit(CalendarFeed(access: .denied))

        default:
            // `.notDetermined`, and `.writeOnly` — which is a grant to add events, not to read
            // them, so from here it is indistinguishable from not having asked.
            Task { [weak self] in
                guard let self else { return }
                let granted = (try? await self.store.requestFullAccessToEvents()) ?? false
                guard self.running else { return }
                if granted {
                    self.query()
                } else {
                    self.report(.denied)
                    self.emit(CalendarFeed(access: .denied))
                }
            }
        }
    }

    // MARK: - Reading

    /// Query the calendar and publish what came back.
    ///
    /// No `store.reset()` first, deliberately. It is the usual cure for EventKit handing back a
    /// stale object, and it is not needed here because nothing is held: every `EKEvent` is
    /// flattened into a ``CalendarEvent`` and dropped inside this method, so each query is already
    /// a fresh answer. It is also not free of consequences — resetting the store is itself a change
    /// to it, and this method runs from the change notification.
    private func query() {
        queue.async { [weak self] in
            guard let self, self.running else { return }

            let now = Date()
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: now)
            // Two days, though only today is ever drawn. The extra day is what a query made at
            // 23:59 needs in order to still hold tomorrow's first event a minute later, and what an
            // announcement lead reaching across midnight counts down to.
            let end =
                calendar.date(byAdding: .day, value: 2, to: start)
                ?? start.addingTimeInterval(2 * 86400)

            let predicate = self.store.predicateForEvents(
                withStart: start, end: end, calendars: self.selectedCalendars())
            let events = self.store.events(matching: predicate).compactMap(Self.convert)

            self.report(.granted)
            self.emit(CalendarFeed(access: .granted, events: events))
        }
    }

    /// Say what perch is allowed to do, once per change of answer.
    ///
    /// Said at all because a widget drawing nothing has two very different causes — an empty
    /// afternoon and a refused permission — and from a terminal they look identical.
    private func report(_ access: CalendarAccess) {
        lock.lock()
        guard reported != access else { return lock.unlock() }
        reported = access
        lock.unlock()

        switch access {
        case .granted:
            Log.calendar.info("reading the calendar")
        case .denied:
            Log.calendar.error(
                "no access to the calendar — grant it in System Settings › Privacy & Security › Calendars"
            )
        case .unknown:
            break
        }
    }

    /// The calendars to read, or nil for all of them.
    ///
    /// A name matching nothing shows nothing, and is reported. perch will not quietly widen a
    /// filter someone wrote on purpose — `calendar-include = Work` typed as `Wrok` should leave you
    /// with an empty panel and a line explaining it, not with your personal calendar on the bezel.
    private func selectedCalendars() -> [EKCalendar]? {
        guard !included.isEmpty else { return nil }

        let all = store.calendars(for: .event)
        let matched = all.filter { included.contains($0.title.lowercased()) }

        let unmatched = included.subtracting(all.map { $0.title.lowercased() })
        if !unmatched.isEmpty, !hasReportedUnmatched {
            hasReportedUnmatched = true
            let wanted = unmatched.sorted().joined(separator: ", ")
            let available = all.map(\.title).sorted().joined(separator: ", ")
            Log.calendar.error(
                "calendar-include names no calendar called \(wanted) — available: \(available)")
        }

        return matched
    }

    /// Flatten an `EKEvent` into something the rest of perch can hold.
    ///
    /// Declined and cancelled events are carried across rather than dropped here. What is worth
    /// drawing is ``Agenda``'s question, and answering it in this file would put it somewhere no
    /// test can reach: `EKEvent.attendees` is read-only, so a fixture for "an invitation you
    /// declined" cannot be built at all.
    ///
    /// - Returns: nil only for an event with no dates, which is not an event.
    private static func convert(_ event: EKEvent) -> CalendarEvent? {
        guard let start = event.startDate, let end = event.endDate else { return nil }

        let mine = event.attendees?.first { $0.isCurrentUser }

        return CalendarEvent(
            itemIdentifier: event.calendarItemIdentifier,
            title: event.title ?? "Untitled",
            start: start,
            end: end,
            isAllDay: event.isAllDay,
            isDeclined: mine?.participantStatus == .declined,
            isCancelled: event.status == .canceled,
            calendarName: event.calendar?.title ?? "",
            color: color(of: event),
            location: event.location,
            joinURL: MeetingLink.find(
                url: event.url, location: event.location, notes: event.notes)
        )
    }

    /// The calendar's colour, converted to sRGB components.
    private static func color(of event: EKEvent) -> EventColor? {
        guard
            let cgColor = event.calendar?.cgColor,
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let converted = cgColor.converted(to: space, intent: .defaultIntent, options: nil),
            let components = converted.components,
            components.count >= 3
        else { return nil }

        return EventColor(
            red: Double(components[0]),
            green: Double(components[1]),
            blue: Double(components[2])
        )
    }

    private func emit(_ feed: CalendarFeed) {
        guard running else { return }
        continuation.yield(feed)
    }
}
