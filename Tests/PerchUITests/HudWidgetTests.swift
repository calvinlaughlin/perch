import PerchCore
import PerchSystem
import Testing

@testable import PerchUI

/// A volume source a test can drive, standing in for CoreAudio.
private final class FakeVolumeSource: VolumeSource, @unchecked Sendable {
    let updates: AsyncStream<VolumeState>
    private let continuation: AsyncStream<VolumeState>.Continuation

    private(set) var started = false
    private(set) var stopped = false

    init() {
        (updates, continuation) = AsyncStream.makeStream(of: VolumeState.self)
    }

    func start() { started = true }
    func stop() {
        stopped = true
        continuation.finish()
    }

    func send(level: Double, muted: Bool = false) {
        continuation.yield(
            VolumeState(level: level, isMuted: muted, deviceName: "Fake Output"))
    }
}

/// Counts announcements without a notch.
@MainActor
private final class SpyAttention: NotchAttention {
    private(set) var peeks = 0
    func requestPeek() { peeks += 1 }
}

@Suite("Volume HUD widget")
@MainActor
struct HudWidgetTests {

    /// Let the widget's listener task drain what the source has yielded.
    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    private func make() -> (HudWidget, FakeVolumeSource, SpyAttention) {
        let source = FakeVolumeSource()
        let widget = HudWidget(source: source)
        let attention = SpyAttention()
        widget.attach(attention: attention)
        widget.activate()
        return (widget, source, attention)
    }

    @Test("The first reading does not announce")
    func firstReadingIsSilent() async {
        // The source emits once on start so the panel knows where things stand. Announcing it
        // would pop the notch open on launch, on every config save, and on every display wake.
        let (widget, source, attention) = make()
        defer { widget.deactivate() }

        source.send(level: 0.5)
        await settle()

        #expect(attention.peeks == 0)
        #expect(widget.state?.level == 0.5)
    }

    @Test("A change announces once")
    func changeAnnounces() async {
        let (widget, source, attention) = make()
        defer { widget.deactivate() }

        source.send(level: 0.5)
        await settle()
        source.send(level: 0.625)
        await settle()

        #expect(attention.peeks == 1)
    }

    @Test("An unchanged reading does not announce again")
    func repeatedReadingIsSilent() async {
        // CoreAudio can emit for reasons that are not a level change — a device property settling,
        // the same value arriving twice. None of those are worth opening the notch for.
        let (widget, source, attention) = make()
        defer { widget.deactivate() }

        source.send(level: 0.5)
        await settle()
        source.send(level: 0.5)
        source.send(level: 0.5)
        await settle()

        #expect(attention.peeks == 0)
    }

    @Test("Muting announces even though the level did not move")
    func muteAnnounces() async {
        // Pressing mute does not change the level, so anything comparing only levels would stay
        // silent for the one keypress whose whole point is that something changed.
        let (widget, source, attention) = make()
        defer { widget.deactivate() }

        source.send(level: 0.5)
        await settle()
        source.send(level: 0.5, muted: true)
        await settle()

        #expect(attention.peeks == 1)
        #expect(widget.state?.effectiveLevel == 0)
    }

    @Test("It has nothing to say until it announces")
    func peekBodyIsGated() async {
        // Unlike media's, which is non-nil whenever there is a track. This is what stops a stale
        // requester resurrecting the HUD into someone else's peek.
        let (widget, source, attention) = make()
        defer { widget.deactivate() }

        source.send(level: 0.5)
        await settle()
        #expect(widget.peekBody == nil)

        source.send(level: 0.75)
        await settle()
        #expect(widget.peekBody != nil)
        #expect(attention.peeks == 1)
    }

    @Test("Deactivating releases the source")
    func deactivateReleasesEverything() async {
        // The rule from CLAUDE.md, and the reason perch can claim to cost nothing idle.
        let (widget, source, _) = make()

        #expect(source.started)
        widget.deactivate()

        #expect(source.stopped)
        #expect(widget.state == nil)
        #expect(widget.peekBody == nil)
    }
}
