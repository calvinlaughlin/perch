import Foundation
import PerchCalendar
import PerchCore
import Testing

@testable import PerchUI

/// An event source a test can drive, standing in for EventKit.
private final class FakeEventSource: EventSource, @unchecked Sendable {

    let updates: AsyncStream<CalendarFeed>
    private let continuation: AsyncStream<CalendarFeed>.Continuation

    private(set) var started = false
    private(set) var stopped = false
    private(set) var refreshes = 0

    init() {
        (updates, continuation) = AsyncStream.makeStream(of: CalendarFeed.self)
    }

    func start() { started = true }

    func stop() {
        stopped = true
        continuation.finish()
    }

    func refresh() { refreshes += 1 }

    func send(_ feed: CalendarFeed) { continuation.yield(feed) }

    func send(_ events: [CalendarEvent]) {
        send(CalendarFeed(access: .granted, events: events))
    }
}

/// Counts announcements without a notch.
@MainActor
private final class SpyAttention: NotchAttention {
    private(set) var peeks = 0
    func requestPeek() { peeks += 1 }
}

@Suite("Calendar widget")
@MainActor
struct CalendarWidgetTests {

    /// Midday, locally.
    ///
    /// Not `Date()`: the widget filters to what is left of *today*, so a test written against the
    /// real clock would pass all day and then fail for the two minutes either side of midnight,
    /// when "three minutes from now" lands on tomorrow.
    private var noon: Date {
        Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
    }

    private func meeting(
        _ title: String,
        at start: Date,
        minutes: Double = 30,
        declined: Bool = false
    ) -> CalendarEvent {
        CalendarEvent(
            itemIdentifier: title,
            title: title,
            start: start,
            end: start.addingTimeInterval(minutes * 60),
            isDeclined: declined
        )
    }

    private func make(
        alert: TimeInterval? = 300
    ) -> (CalendarWidget, FakeEventSource, SpyAttention) {
        let source = FakeEventSource()
        let now = noon
        let widget = CalendarWidget(source: source, alert: alert, clock: { now })
        let attention = SpyAttention()
        widget.attach(attention: attention)
        widget.activate()
        return (widget, source, attention)
    }

    /// Let the widget's listener task drain what the source has yielded.
    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    // MARK: - Announcing

    @Test("A meeting inside the lead is announced")
    func meetingsInsideTheLeadAnnounce() async {
        let (widget, source, attention) = make()
        defer { widget.deactivate() }

        source.send([meeting("Standup", at: noon.addingTimeInterval(180))])
        await settle()

        #expect(attention.peeks == 1)
        #expect(widget.peekBody != nil)
    }

    @Test("It is announced once, not once per update")
    func meetingsAreAnnouncedOnce() async {
        // The calendar emits on every change, and the widget's own timer ticks through the whole
        // five minutes before a meeting. Either one re-announcing would mean the notch opening
        // over and over for something the user was told about already.
        let (widget, source, attention) = make()
        defer { widget.deactivate() }

        let standup = [meeting("Standup", at: noon.addingTimeInterval(180))]
        source.send(standup)
        await settle()
        source.send(standup)
        source.send(standup)
        await settle()

        #expect(attention.peeks == 1)
    }

    @Test("Two meetings are two announcements")
    func separateMeetingsAnnounceSeparately() async {
        let (widget, source, attention) = make()
        defer { widget.deactivate() }

        source.send([meeting("Standup", at: noon.addingTimeInterval(180))])
        await settle()
        source.send([
            meeting("Standup", at: noon.addingTimeInterval(180)),
            meeting("Review", at: noon.addingTimeInterval(240)),
        ])
        await settle()

        #expect(attention.peeks == 2)
    }

    @Test("A meeting beyond the lead waits its turn")
    func distantMeetingsAreSilent() async {
        let (widget, source, attention) = make()
        defer { widget.deactivate() }

        source.send([meeting("Standup", at: noon.addingTimeInterval(1800))])
        await settle()

        #expect(attention.peeks == 0)
        #expect(widget.peekBody == nil)
    }

    @Test("A meeting already under way is never announced")
    func startedMeetingsAreSilent() async {
        let (widget, source, attention) = make()
        defer { widget.deactivate() }

        source.send([meeting("Standup", at: noon.addingTimeInterval(-120))])
        await settle()

        #expect(attention.peeks == 0)
    }

    @Test("A declined meeting is not announced")
    func declinedMeetingsAreSilent() async {
        let (widget, source, attention) = make()
        defer { widget.deactivate() }

        source.send([meeting("Optional", at: noon.addingTimeInterval(180), declined: true)])
        await settle()

        #expect(attention.peeks == 0)
    }

    @Test("With alerts off it announces nothing and watches nothing")
    func alertsOffMeansSilence() async {
        // Both halves matter: `alert = never` is also what makes this widget stop running behind a
        // closed notch, because there is then nothing it could be watching for.
        let (widget, source, attention) = make(alert: nil)
        defer { widget.deactivate() }

        #expect(!widget.runsWhileHidden)

        source.send([meeting("Standup", at: noon.addingTimeInterval(180))])
        await settle()

        #expect(attention.peeks == 0)
        #expect(widget.peekBody == nil)
    }

    @Test("It has nothing to say until it announces")
    func peekBodyIsGated() async {
        // The volume HUD's shape rather than media's. Unconditional, a track change would show the
        // user their next meeting instead of the track that changed.
        let (widget, source, _) = make()
        defer { widget.deactivate() }

        #expect(widget.peekBody == nil)

        source.send([meeting("Standup", at: noon.addingTimeInterval(180))])
        await settle()

        #expect(widget.peekBody != nil)
    }

    // MARK: - Access

    @Test("A refusal is not an announcement")
    func deniedAccessSaysNothing() async {
        let (widget, source, attention) = make()
        defer { widget.deactivate() }

        source.send(CalendarFeed(access: .denied))
        await settle()

        #expect(attention.peeks == 0)
        #expect(widget.peekBody == nil)
        #expect(widget.upcoming.isEmpty)
    }

    // MARK: - Lifecycle

    @Test("Deactivating releases the source")
    func deactivateReleasesEverything() async {
        // The rule from CLAUDE.md, and the reason perch can claim to cost nothing idle.
        let (widget, source, _) = make()

        #expect(source.started)

        source.send([meeting("Standup", at: noon.addingTimeInterval(180))])
        await settle()
        widget.deactivate()

        #expect(source.stopped)
        #expect(widget.peekBody == nil)
    }

    @Test("What it knows survives a close and reopen")
    func theAgendaSurvivesReopening() async {
        // Media's reasoning: clearing everything means each reopen draws an empty panel that then
        // fills in, which reads as the widget having failed and then recovered.
        let (widget, source, _) = make()

        source.send([meeting("Review", at: noon.addingTimeInterval(1800))])
        await settle()
        widget.deactivate()

        #expect(widget.upcoming.map(\.title) == ["Review"])
    }

    // MARK: - Settings

    @Test("alert = never turns the announcement off")
    func neverParsesAsNoAlert() throws {
        let widget = try CalendarWidget(
            settings: WidgetSettings(kind: "calendar", values: ["alert": "never"]))

        #expect(!widget.runsWhileHidden)
    }

    @Test("An alert perch cannot parse names the key as it was written")
    func badAlertReadsAsAConfigDiagnostic() {
        // It has to arrive as an ordinary config diagnostic naming `calendar-alert`, not as a
        // widget that fails to build and takes the panel's other cards with it.
        #expect(throws: ConfigValueError.self) {
            _ = try CalendarWidget(
                settings: WidgetSettings(kind: "calendar", values: ["alert": "soonish"]))
        }
    }

    @Test("A bare widget = calendar is a working widget")
    func defaultsAreWorthShipping() throws {
        let widget = try CalendarWidget(settings: WidgetSettings(kind: "calendar"))

        #expect(widget.placement == .expanded)
        #expect(widget.runsWhileHidden)
    }
}
