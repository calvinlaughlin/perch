import Foundation

/// What is playing right now, as far as the system knows.
///
/// Every field but `bundleIdentifier` is optional, and that is not defensiveness: different
/// players report wildly different subsets. Spotify sends album, track numbers, and artwork;
/// a browser playing a video may send a title and nothing else. A model that insisted on more
/// would simply drop those sources.
public struct NowPlaying: Equatable, Sendable {

    /// The app the audio belongs to, e.g. `com.spotify.client`.
    public var bundleIdentifier: String

    public var title: String?
    public var artist: String?
    public var album: String?

    /// Whether it is actually playing, as opposed to paused with a track loaded.
    public var isPlaying: Bool

    /// Track length in seconds.
    public var duration: TimeInterval?

    /// How far in, in seconds, *as of `timestamp`*.
    ///
    /// This is a snapshot, not a live counter — the system reports it once and it does not tick.
    /// Anything showing a progress bar has to extrapolate from `timestamp`, which is what
    /// `elapsed(at:)` does.
    public var elapsedTime: TimeInterval?

    /// When `elapsedTime` was measured.
    public var timestamp: Date?

    /// Raw artwork bytes, in whatever format `artworkMimeType` names.
    ///
    /// Held as data rather than a decoded image so this type stays free of AppKit and remains
    /// testable. Decoding happens in the UI layer, off the main thread.
    public var artworkData: Data?
    public var artworkMimeType: String?

    public init(
        bundleIdentifier: String,
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        isPlaying: Bool = false,
        duration: TimeInterval? = nil,
        elapsedTime: TimeInterval? = nil,
        timestamp: Date? = nil,
        artworkData: Data? = nil,
        artworkMimeType: String? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.duration = duration
        self.elapsedTime = elapsedTime
        self.timestamp = timestamp
        self.artworkData = artworkData
        self.artworkMimeType = artworkMimeType
    }

    /// Where playback has reached at a given moment.
    ///
    /// Extrapolates from the last reported position, since the system reports elapsed time once
    /// per change rather than continuously. Clamped to `duration` so a progress bar cannot run off
    /// the end when a track finishes and no update has arrived yet.
    public func elapsed(at moment: Date = Date()) -> TimeInterval? {
        guard let elapsedTime else { return nil }
        guard isPlaying, let timestamp else { return elapsedTime }

        let projected = elapsedTime + max(0, moment.timeIntervalSince(timestamp))
        guard let duration else { return projected }
        return min(projected, duration)
    }

    /// How far through the track, 0...1, or nil when the length is unknown.
    public func progress(at moment: Date = Date()) -> Double? {
        guard let duration, duration > 0, let elapsed = elapsed(at: moment) else { return nil }
        return min(1, max(0, elapsed / duration))
    }

    /// Whether there is enough here to show something meaningful.
    ///
    /// A payload with no title is a player that has registered but has nothing loaded — showing
    /// a blank row for it is worse than showing nothing.
    public var isPresentable: Bool {
        !(title ?? "").isEmpty
    }
}
