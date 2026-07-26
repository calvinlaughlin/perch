import Foundation
import Testing

@testable import PerchMedia

/// Build one line of adapter output.
private func line(_ payload: String, diff: Bool = false) -> String {
    #"{"type":"data","diff":\#(diff),"payload":\#(payload)}"#
}

private let spotify = """
    {"bundleIdentifier":"com.spotify.client","title":"Grey Luh","artist":"Berhana",
     "album":"Berhana","playing":true,"duration":261,"elapsedTime":71.911,
     "timestamp":"2026-07-26T02:10:42Z","artworkMimeType":"image/jpeg"}
    """

@Suite("Media stream decoding")
struct MediaStreamDecoderTests {

    @Test("A full payload becomes a now-playing value")
    func decodesFullPayload() throws {
        var decoder = MediaStreamDecoder()

        let event = decoder.decode(line: line(spotify))

        guard case .updated(let playing) = event else {
            Issue.record("expected .updated, got \(event)")
            return
        }
        #expect(playing.bundleIdentifier == "com.spotify.client")
        #expect(playing.title == "Grey Luh")
        #expect(playing.artist == "Berhana")
        #expect(playing.isPlaying)
        #expect(playing.duration == 261)
    }

    @Test("An empty payload means nothing is playing")
    func emptyPayloadClears() {
        var decoder = MediaStreamDecoder()
        _ = decoder.decode(line: line(spotify))

        let event = decoder.decode(line: line("{}"))

        #expect(event == .cleared)
        #expect(decoder.current == nil)
    }

    @Test("An empty payload before anything played is not a change")
    func emptyPayloadFirstIsUnchanged() {
        // Every stream opens with one of these; treating it as a change would flash the UI.
        var decoder = MediaStreamDecoder()

        #expect(decoder.decode(line: line("{}")) == .unchanged)
    }

    @Test("A diff updates only what it carries")
    func diffKeepsUnmentionedFields() throws {
        // This is the whole reason diffs exist: a pause must not re-send the artwork.
        var decoder = MediaStreamDecoder()
        _ = decoder.decode(line: line(spotify))

        _ = decoder.decode(line: line(#"{"playing":false}"#, diff: true))

        let current = try #require(decoder.current)
        #expect(current.isPlaying == false)
        #expect(current.title == "Grey Luh")  // preserved
        #expect(current.duration == 261)  // preserved
    }

    @Test("A diff naming a different app does not inherit the old track")
    func diffFromAnotherAppDoesNotInherit() throws {
        // Otherwise one app's title and artwork would appear under another app's name.
        var decoder = MediaStreamDecoder()
        _ = decoder.decode(line: line(spotify))

        _ = decoder.decode(
            line: line(#"{"bundleIdentifier":"com.apple.Music","playing":true}"#, diff: true)
        )

        let current = try #require(decoder.current)
        #expect(current.bundleIdentifier == "com.apple.Music")
        #expect(current.title == nil)
        #expect(current.album == nil)
    }

    @Test("Artwork is decoded from base64")
    func decodesArtwork() throws {
        var decoder = MediaStreamDecoder()
        let encoded = Data("not really a jpeg".utf8).base64EncodedString()

        _ = decoder.decode(
            line: line(
                #"{"bundleIdentifier":"x","title":"t","artworkData":"\#(encoded)"}"#
            )
        )

        let artwork = try #require(decoder.current?.artworkData)
        #expect(String(decoding: artwork, as: UTF8.self) == "not really a jpeg")
    }

    @Test("A repeated identical line is not a change")
    func identicalLineIsUnchanged() {
        // The adapter can re-emit; redrawing for those would be wasted work every time.
        var decoder = MediaStreamDecoder()
        _ = decoder.decode(line: line(spotify))

        #expect(decoder.decode(line: line(spotify)) == .unchanged)
    }

    @Test("A malformed line is reported and does not disturb the current state")
    func malformedLineKeepsState() throws {
        var decoder = MediaStreamDecoder()
        _ = decoder.decode(line: line(spotify))

        let event = decoder.decode(line: "{ this is not json")

        guard case .malformed = event else {
            Issue.record("expected .malformed, got \(event)")
            return
        }
        #expect(decoder.current?.title == "Grey Luh")
    }

    @Test("Blank lines are ignored")
    func ignoresBlankLines() {
        var decoder = MediaStreamDecoder()

        #expect(decoder.decode(line: "") == .unchanged)
        #expect(decoder.decode(line: "   \n") == .unchanged)
    }

    @Test("Fractional-second timestamps parse")
    func parsesFractionalTimestamps() throws {
        var decoder = MediaStreamDecoder()

        _ = decoder.decode(
            line: line(
                #"{"bundleIdentifier":"x","title":"t","timestamp":"2026-07-26T02:10:42.500Z"}"#
            )
        )

        #expect(decoder.current?.timestamp != nil)
    }

    @Test("Recorded output from a real player decodes")
    func decodesRecordedStream() throws {
        // Captured from Spotify on macOS 15.7.3 with adapter v0.7.6, so the field names are the
        // ones the adapter actually emits rather than the ones its README documents.
        let url = try #require(
            Bundle.module.url(
                forResource: "stream", withExtension: "jsonl", subdirectory: "Fixtures")
        )
        let contents = try String(contentsOf: url, encoding: .utf8)

        var decoder = MediaStreamDecoder()
        var updates = 0
        for line in contents.split(separator: "\n") {
            if case .malformed(let reason) = decoder.decode(line: String(line)) {
                Issue.record("fixture line failed to decode: \(reason)")
            }
            if decoder.current != nil { updates += 1 }
        }

        #expect(updates > 0)
        #expect(decoder.current?.bundleIdentifier == "com.spotify.client")
    }
}

@Suite("Playback position")
struct NowPlayingProgressTests {

    private func track(elapsed: TimeInterval, playing: Bool, at instant: Date) -> NowPlaying {
        NowPlaying(
            bundleIdentifier: "x", title: "t", isPlaying: playing,
            duration: 100, elapsedTime: elapsed, timestamp: instant
        )
    }

    @Test("A paused track's position does not move")
    func pausedPositionIsStatic() {
        let now = Date()
        let paused = track(elapsed: 30, playing: false, at: now)

        #expect(paused.elapsed(at: now.addingTimeInterval(60)) == 30)
    }

    @Test("A playing track's position is extrapolated from when it was measured")
    func playingPositionAdvances() throws {
        // The system reports elapsed time once per change, not continuously, so anything showing
        // progress has to project it forward or the bar sits still while music plays.
        let now = Date()
        let playing = track(elapsed: 30, playing: true, at: now)

        let elapsed = try #require(playing.elapsed(at: now.addingTimeInterval(10)))
        #expect(abs(elapsed - 40) < 0.01)
    }

    @Test("Projection is clamped to the track length")
    func projectionIsClamped() {
        // When a track ends and the next update has not arrived, an unclamped bar runs off the end.
        let now = Date()
        let playing = track(elapsed: 95, playing: true, at: now)

        #expect(playing.elapsed(at: now.addingTimeInterval(600)) == 100)
        #expect(playing.progress(at: now.addingTimeInterval(600)) == 1)
    }

    @Test("Progress is nil when the length is unknown")
    func progressNeedsDuration() {
        let unknown = NowPlaying(bundleIdentifier: "x", elapsedTime: 10)

        #expect(unknown.progress() == nil)
    }

    @Test("A track with no title is not worth showing")
    func untitledIsNotPresentable() {
        // A player that has registered but loaded nothing; a blank row is worse than no row.
        #expect(!NowPlaying(bundleIdentifier: "x").isPresentable)
        #expect(NowPlaying(bundleIdentifier: "x", title: "t").isPresentable)
    }
}
