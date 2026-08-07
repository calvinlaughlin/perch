import Foundation
import Testing

@testable import PerchMedia

@Suite("Seeking")
struct SeekingTests {

    private func track(duration: TimeInterval?) -> NowPlaying {
        NowPlaying(bundleIdentifier: "x", title: "t", duration: duration, elapsedTime: 0)
    }

    @Test("A fraction of the bar is that fraction of the track")
    func fractionMapsToSeconds() {
        let playing = track(duration: 240)

        #expect(playing.seekTarget(fraction: 0) == 0)
        #expect(playing.seekTarget(fraction: 0.5) == 120)
        #expect(playing.seekTarget(fraction: 1) == 240)
    }

    @Test("A drag past either end lands on the end")
    func fractionIsClamped() {
        // The pointer leaves the bar constantly — the panel is 420 points wide and the gesture
        // keeps reporting after it has gone.
        let playing = track(duration: 240)

        #expect(playing.seekTarget(fraction: -3) == 0)
        #expect(playing.seekTarget(fraction: 4) == 240)
        #expect(playing.seekTarget(fraction: .nan) == nil)
    }

    @Test("A track with no length cannot be seeked into")
    func lengthlessTrackHasNoTarget() {
        // Live streams and most browser audio. A bar with no end has no two-thirds mark.
        #expect(track(duration: nil).seekTarget(fraction: 0.5) == nil)
        #expect(track(duration: 0).seekTarget(fraction: 0.5) == nil)
    }

    @Test("The adapter is asked in microseconds")
    func seekArgumentsAreMicroseconds() {
        // The trap this test exists for: every position perch handles is seconds, and the adapter
        // takes microseconds. Seconds passed straight through is a seek to the very start that
        // looks plausible for the first few seconds of a track.
        #expect(MediaRemoteAdapterSource.seekArguments(0) == ["seek", "0"])
        #expect(MediaRemoteAdapterSource.seekArguments(1) == ["seek", "1000000"])
        #expect(MediaRemoteAdapterSource.seekArguments(93.5) == ["seek", "93500000"])
    }

    @Test("Nonsense positions do not reach the adapter as nonsense")
    func seekArgumentsAreDefended() {
        // The adapter documents a positive integer; a negative or non-finite one is a fail from
        // the perl side, and `Int(Double.infinity)` traps outright.
        #expect(MediaRemoteAdapterSource.seekArguments(-10) == ["seek", "0"])
        #expect(MediaRemoteAdapterSource.seekArguments(.nan) == ["seek", "0"])
        #expect(MediaRemoteAdapterSource.seekArguments(.infinity) == ["seek", "0"])
        #expect(MediaRemoteAdapterSource.seekArguments(1e30) == ["seek", String(Int.max)])
    }
}

@Suite("Time codes")
struct TimeCodeTests {

    @Test("Positions read the way a player writes them")
    func formatsAsMinutesAndSeconds() {
        #expect(TimeCode.text(0) == "0:00")
        #expect(TimeCode.text(9) == "0:09")
        #expect(TimeCode.text(69) == "1:09")
        #expect(TimeCode.text(183) == "3:03")
        #expect(TimeCode.text(599) == "9:59")
    }

    @Test("An hour gains a field, and everything below it stays padded")
    func formatsHours() {
        // A podcast, a DJ set, a film. `1:05` must not be ambiguous between 65 seconds and 65
        // minutes, which is what dropping the hour field would make it.
        #expect(TimeCode.text(3600) == "1:00:00")
        #expect(TimeCode.text(3665) == "1:01:05")
        #expect(TimeCode.text(45296) == "12:34:56")
    }

    @Test("Seconds are floored, not rounded")
    func flooring() {
        // Rounding shows 0:01 before the first second has elapsed, and shows the full duration
        // for the last half second of a track.
        #expect(TimeCode.text(0.9) == "0:00")
        #expect(TimeCode.text(59.99) == "0:59")
    }

    @Test("Nothing sensible reads as nothing")
    func rejectsNonsense() {
        #expect(TimeCode.text(-1) == TimeCode.placeholder)
        #expect(TimeCode.text(.nan) == TimeCode.placeholder)
        #expect(TimeCode.text(.infinity) == TimeCode.placeholder)
    }
}
