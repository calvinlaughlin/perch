import AppKit
import Foundation
import PerchCalendar
import PerchCore
import SwiftUI

/// Shows what is next on your calendar.
///
/// Three surfaces, all of the same handful of events: an agenda of what is left of today in the open
/// panel, one line in the collapsed strip, and an announcement a few minutes before a meeting
/// starts. The last is the one that justifies the widget — a heads-up where your eyes already are,
/// which is the thing a notch can do that a notification centre cannot.
///
/// The rules about *which* event and *when* live in `PerchCalendar.Agenda`, where they can be tested
/// at any hour of any day. What is left here is lifecycle, drawing, and the two clicks.
@MainActor
@Observable
public final class CalendarWidget: NotchWidget {

    public static let kind = "calendar"

    public static let summary = "Shows what is next on your calendar."

    public static let settings: [WidgetSetting] = [
        WidgetSetting(
            name: "placement", syntax: "leading | trailing | expanded", defaultValue: "expanded",
            documentation:
                "Where the widget draws. The strips need collapsed-bleed to have room."),
        WidgetSetting(
            name: "alert", syntax: "duration | never", defaultValue: "5m",
            documentation:
                "How far ahead of an event to announce it. Announced once, and never for one already under way."
        ),
        WidgetSetting(
            name: "include", syntax: "names, comma-separated", defaultValue: "every calendar",
            documentation: "Only read these calendars, by name."),
        WidgetSetting(
            name: "24-hour", syntax: "true | false", defaultValue: "false",
            documentation: "Use a 24-hour clock."),
    ]

    public let placement: Placement

    /// How far ahead to announce, or nil for never.
    private let alert: TimeInterval?

    private let included: Set<String>
    private let usesTwentyFourHour: Bool

    private var source: (any EventSource)?
    private var listener: Task<Void, Never>?

    /// The one timer this widget has, asleep until the next thing that changes what is drawn.
    private var waker: Task<Void, Never>?

    private var attention: (any NotchAttention)?

    /// What the calendar last said, and whether perch is allowed to ask.
    fileprivate private(set) var feed = CalendarFeed(access: .unknown)

    /// The moment the agenda is drawn against.
    ///
    /// Passed in rather than read at draw time so every rule below is a pure function of a date,
    /// and so a repaint mid-minute cannot disagree with the countdown that scheduled it.
    fileprivate private(set) var now: Date

    /// Occurrences already announced, so a meeting is announced once and not once a minute.
    private var announced: Set<String> = []

    /// The event currently being announced, or nil when this widget has nothing to say.
    fileprivate private(set) var announcement: CalendarEvent?
    private var announcementExpiry: Task<Void, Never>?

    /// Whether the agenda is actually on screen, which decides whether minute boundaries matter.
    private var isOnScreen = false

    /// The day the current events were queried for, so the window can be re-read when it rolls.
    private var queriedDay: Date?

    /// Where `now` comes from.
    ///
    /// One seam rather than a `Date()` at each of the six places that needs one. Tests set it so
    /// that "an event three minutes from now" means the same thing at every hour — including the
    /// two minutes either side of midnight, where a real clock would put the event on tomorrow's
    /// agenda and quietly stop announcing it.
    private let clock: () -> Date

    public init(settings: WidgetSettings) throws {
        placement = try settings.enumeration("placement", default: .expanded)

        let raw = settings.string("alert", default: "5m").trimmingCharacters(in: .whitespaces)
        if raw.lowercased() == "never" {
            alert = nil
        } else {
            let lead = try settings.duration("alert", default: .seconds(300))
            let seconds = TimeInterval(lead.components.seconds)
            // A lead of zero would only ever fire for an event that has already started, which is
            // what `never` means said the long way round.
            alert = seconds > 0 ? seconds : nil
        }

        included = Set(
            settings.string("include", default: "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )

        usesTwentyFourHour = try settings.bool("24-hour", default: false)
        clock = { Date() }
        now = Date()
    }

    /// For tests: build against a supplied source and a supplied clock, never touching the real
    /// calendar or the real time.
    init(
        source: any EventSource,
        placement: Placement = .expanded,
        alert: TimeInterval? = 300,
        clock: @escaping () -> Date = { Date() }
    ) {
        self.source = source
        self.placement = placement
        self.alert = alert
        self.included = []
        self.usesTwentyFourHour = false
        self.clock = clock
        self.now = clock()
    }

    /// Keeps working while hidden only when it has something to announce.
    ///
    /// An announcement cannot be made by something that is not watching, so `calendar-alert` has to
    /// buy a widget that stays active behind a closed notch. With `alert = never` there is nothing
    /// to watch *for*, and an agenda nobody is looking at should cost nothing at all.
    ///
    /// What the promise costs when it is made: one EventKit change observer and one task asleep
    /// until the next event boundary. Nothing polls, and no subprocess is spawned.
    public var runsWhileHidden: Bool { alert != nil }

    public func attach(attention: any NotchAttention) {
        self.attention = attention
    }

    public func activate() {
        guard listener == nil else { return }

        // Built here rather than in `init` so a widget that is configured but never shown never
        // asks for the calendar permission — the prompt should arrive because you put perch's
        // calendar on screen, not because perch launched.
        let source = source ?? EventKitSource(including: included)
        self.source = source

        source.start()
        listener = Task { [weak self] in
            for await feed in source.updates {
                guard !Task.isCancelled else { return }
                self?.receive(feed)
            }
        }

        now = clock()
        queriedDay = Calendar.current.startOfDay(for: now)
        scheduleWake()
    }

    public func deactivate() {
        listener?.cancel()
        listener = nil
        waker?.cancel()
        waker = nil
        announcementExpiry?.cancel()
        announcementExpiry = nil
        announcement = nil
        source?.stop()
        source = nil
        isOnScreen = false

        // Deliberately keeps `feed` and `announced`, on the same reasoning as media keeping the
        // current track: clearing them means every reopen draws "Nothing left today" for the frame
        // before the query answers, and an event announced before the display slept would be
        // announced again when it woke.
    }

    public func setVisible(_ visible: Bool) {
        isOnScreen = visible

        // A closed notch has no countdown to keep current, so the minute boundaries stop being
        // worth waking for — and reopening should show the right minute in its first frame rather
        // than up to a minute late.
        if visible { now = clock() }
        scheduleWake()
    }

    // MARK: - Events

    private func receive(_ feed: CalendarFeed) {
        self.feed = feed
        now = clock()
        pruneAnnounced()
        announceIfDue()
        scheduleWake()
    }

    /// What is left of today, which is what all three surfaces draw.
    ///
    /// Internal rather than fileprivate like its neighbours: it is the widget's whole answer, so it
    /// is what the tests assert against.
    var upcoming: [CalendarEvent] {
        Agenda.upcoming(from: feed.events, at: now)
    }

    /// The event the strip shows and the countdown counts down to.
    fileprivate var focus: CalendarEvent? {
        Agenda.focus(in: upcoming, at: now)
    }

    /// Wake up, redraw, and work out when to do it again.
    private func tick() {
        now = clock()

        // The only thing a change notification cannot tell us about: the window itself moving.
        let today = Calendar.current.startOfDay(for: now)
        if today != queriedDay {
            queriedDay = today
            source?.refresh()
        }

        pruneAnnounced()
        announceIfDue()
        scheduleWake()
    }

    private func scheduleWake() {
        waker?.cancel()

        let target = Agenda.nextWake(
            after: now, events: upcoming, lead: alert, showsCountdown: isOnScreen)
        let delay = max(1, target.timeIntervalSince(clock()))

        waker = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.tick()
        }
    }

    /// Announce the next meeting, once, when it comes within the lead.
    ///
    /// The first one not already announced, rather than the soonest: two meetings can fall inside
    /// the lead together, and taking only the soonest would leave the second silent until the first
    /// began. One at a time either way — a peek is one thing being announced.
    private func announceIfDue() {
        guard let alert else { return }
        let due = Agenda.alertable(in: upcoming, at: now, lead: alert)
        guard let event = due.first(where: { !announced.contains($0.id) }) else { return }

        announced.insert(event.id)
        announcement = event
        attention?.requestPeek()

        // Outlive the peek slightly, exactly as the volume HUD does: `peekBody` is read while the
        // panel animates shut, and dropping the content mid-collapse makes the notch appear to
        // empty before it closes.
        announcementExpiry?.cancel()
        announcementExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.announcement = nil
        }
    }

    /// Forget events that are no longer in the window.
    ///
    /// Without this the set grows for as long as perch runs. It is a few dozen strings a day rather
    /// than a leak worth worrying about, but "release everything you own" is easier to keep than to
    /// re-establish.
    private func pruneAnnounced() {
        let live = Set(feed.events.map(\.id))
        announced.formIntersection(live)
    }

    // MARK: - Drawing

    public var body: AnyView {
        switch placement {
        case .expanded:
            AnyView(CalendarCardView(widget: self, format: format))
        case .leading, .trailing:
            AnyView(CalendarStripView(widget: self, format: format))
        }
    }

    /// Gated on there being a live announcement, the way the volume HUD's is.
    ///
    /// Unconditionally non-nil — media's shape — would mean a volume change or a track change
    /// showed the user their next meeting instead of what actually changed.
    public var peekBody: AnyView? {
        guard announcement != nil else { return nil }
        return AnyView(CalendarPeekView(widget: self, format: format))
    }

    fileprivate var format: Date.FormatStyle {
        Date.FormatStyle.dateTime
            .hour(
                usesTwentyFourHour ? .twoDigits(amPM: .omitted) : .defaultDigits(amPM: .abbreviated)
            )
            .minute(.twoDigits)
    }

    // MARK: - The two clicks

    /// Show the event in Calendar.app.
    fileprivate func reveal(_ event: CalendarEvent) {
        CalendarApp.reveal(event)
    }

    /// Join the meeting the event carries a link to.
    fileprivate func join(_ event: CalendarEvent) {
        guard let url = event.joinURL else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Opening Calendar.app at a particular event.
///
/// `ical://ekevent/<start>/<item>` is the URL Calendar.app itself hands out, and the start stamp is
/// not optional padding: without it a recurring event opens at whichever occurrence Calendar feels
/// like. If the system cannot open it — a Mac where something else owns the `ical` scheme, or an
/// event that has since been deleted — opening Calendar itself is a better answer than a click that
/// visibly does nothing.
private enum CalendarApp {

    static func reveal(_ event: CalendarEvent) {
        if let url = url(for: event), NSWorkspace.shared.open(url) { return }
        guard let fallback = URL(string: "ical://") else { return }
        NSWorkspace.shared.open(fallback)
    }

    static func url(for event: CalendarEvent) -> URL? {
        let stamp = stampFormatter.string(from: event.start)
        return URL(
            string: "ical://ekevent/\(stamp)/\(event.itemIdentifier)?method=show&options=more")
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

// MARK: - The card

/// The agenda in the open panel: what is left of today, as many rows as the panel is tall.
private struct CalendarCardView: View {

    let widget: CalendarWidget
    let format: Date.FormatStyle

    var body: some View {
        let events = widget.upcoming

        return Group {
            if widget.feed.access == .denied {
                message(
                    "Calendar access is off — System Settings › Privacy & Security › Calendars",
                    identifier: "calendar.denied")
            } else if !events.isEmpty {
                agenda(events)
            } else if widget.feed.access == .granted {
                message("Nothing left today", identifier: "calendar.empty")
            }
            // Access still unsettled and nothing to show: deliberately blank. Saying "nothing left
            // today" before the system has answered is perch answering for it, and saying "no
            // access" is accusing the user of a refusal they have not made.
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("calendar.container")
    }

    private func agenda(_ events: [CalendarEvent]) -> some View {
        GeometryReader { proxy in
            let rows = PanelMetrics.agendaRows(inHeight: proxy.size.height)
            let visible = Agenda.rows(from: events, limit: rows)
            let focus = widget.focus

            VStack(spacing: PanelMetrics.agendaGap) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, event in
                    AgendaRow(
                        widget: widget,
                        event: event,
                        index: index,
                        isFocus: event.id == focus?.id,
                        format: format
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func message(_ text: String, identifier: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.4))
            .lineLimit(2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier(identifier)
    }
}

/// One line of the agenda.
///
/// The row is a button that opens the event, and the join link is a second button beside it rather
/// than one nested inside it. Nesting reads better in a diagram and behaves worse in practice: the
/// outer button takes the click, and joining a meeting becomes a game of hitting eleven points.
private struct AgendaRow: View {

    let widget: CalendarWidget
    let event: CalendarEvent
    let index: Int
    let isFocus: Bool
    let format: Date.FormatStyle

    @State private var isPointedAt = false

    var body: some View {
        HStack(spacing: PanelMetrics.columnGap) {
            accent

            Button {
                widget.reveal(event)
            } label: {
                content
            }
            .buttonStyle(.plain)
            .onHover { isPointedAt = $0 }
            .help("Show in Calendar")
            .accessibilityLabel("\(event.title), show in Calendar")

            if event.joinURL != nil { joinButton }
        }
        .frame(height: PanelMetrics.agendaRow)
    }

    private var content: some View {
        HStack(spacing: PanelMetrics.columnGap) {
            Text(time)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(isFocus ? 0.9 : 0.5))
                .lineLimit(1)
                .frame(width: PanelMetrics.agendaTime, alignment: .leading)
                .accessibilityIdentifier("calendar.row.\(index).time")

            Text(event.title)
                .font(.system(size: 12, weight: isFocus ? .semibold : .regular))
                .foregroundStyle(.white.opacity(isFocus ? 1 : 0.6))
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityIdentifier("calendar.row.\(index).title")

            Spacer(minLength: PanelMetrics.unit)

            if isFocus, let countdown = EventPhrase.countdown(to: event.start, at: widget.now) {
                Text(countdown)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .accessibilityIdentifier("calendar.countdown")
            }
        }
        // Claimed rather than requested, so the whole row is the target and the title's own width
        // does not decide where the countdown sits.
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .opacity(isPointedAt ? 0.7 : 1)
        .animation(.easeOut(duration: 0.12), value: isPointedAt)
    }

    /// The time column: a clock time, or the fact that there is no time to give.
    private var time: String {
        event.isAllDay ? "all-day" : event.start.formatted(format)
    }

    private var accent: some View {
        Capsule()
            .fill(AgendaPalette.color(of: event))
            .frame(width: PanelMetrics.agendaAccent, height: PanelMetrics.agendaRow / 2)
    }

    private var joinButton: some View {
        Button {
            widget.join(event)
        } label: {
            Image(systemName: "video.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: PanelMetrics.agendaRow, height: PanelMetrics.agendaRow)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Join \(event.title)")
        .accessibilityLabel("Join \(event.title)")
        .accessibilityIdentifier("calendar.row.\(index).join")
    }
}

// MARK: - The strip

/// One line beside the camera housing: the next thing, and when.
///
/// Draws nothing at all when there is nothing next. An empty evening should give the bezel back
/// rather than leave a placeholder welded to it.
private struct CalendarStripView: View {

    let widget: CalendarWidget
    let format: Date.FormatStyle

    var body: some View {
        if let event = widget.focus {
            HStack(spacing: PanelMetrics.unit * 2) {
                Capsule()
                    .fill(AgendaPalette.color(of: event))
                    .frame(width: 2, height: PanelMetrics.unit * 3)

                Text(
                    EventPhrase.countdown(to: event.start, at: widget.now)
                        ?? event.start.formatted(format)
                )
                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .fixedSize()

                Text(event.title)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            // The strip is not a control. Clicking the notch toggles the panel even under
            // `open-on = hover`, and a widget that swallowed those clicks would take away the only
            // way to dismiss it without moving the pointer.
            .allowsHitTesting(false)
            .accessibilityIdentifier("calendar.strip")
        }
    }
}

// MARK: - The peek

/// The announcement: one meeting, how long until it, and nothing to press.
private struct CalendarPeekView: View {

    let widget: CalendarWidget
    let format: Date.FormatStyle

    var body: some View {
        if let event = widget.announcement {
            HStack(spacing: PanelMetrics.columnGap) {
                Capsule()
                    .fill(AgendaPalette.color(of: event))
                    .frame(width: PanelMetrics.agendaAccent, height: PanelMetrics.unit * 7)

                VStack(alignment: .leading, spacing: PanelMetrics.textGap / 2) {
                    Text(event.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .accessibilityIdentifier("calendar.peek.title")

                    Text(subtitle(for: event))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .accessibilityIdentifier("calendar.peek.subtitle")
                }

                Spacer(minLength: 0)
            }
        }
    }

    /// How long until it, then when it is — in that order, because the first is why you looked up.
    private func subtitle(for event: CalendarEvent) -> String {
        let lead = EventPhrase.announcement(to: event.start, at: widget.now)
        return "\(lead) · \(event.start.formatted(format))"
    }
}

// MARK: - Colour

/// Turns a calendar's colour into something drawable.
private enum AgendaPalette {

    /// The calendar's own colour, or a neutral bar for one that has none.
    ///
    /// Calendar colours are the only thing on the panel that says which part of your life an event
    /// belongs to, which is worth four points of width.
    static func color(of event: CalendarEvent) -> Color {
        guard let color = event.color else { return .white.opacity(0.35) }
        return Color(red: color.red, green: color.green, blue: color.blue)
    }
}
