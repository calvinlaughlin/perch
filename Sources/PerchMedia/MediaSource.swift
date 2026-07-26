import Foundation

/// Commands a player can be asked to perform.
///
/// Raw values are the adapter's command identifiers. They are an implementation detail of one
/// source and would not survive a different backend, which is exactly why they are hidden behind
/// this enum rather than sprinkled through the UI as magic numbers.
public enum MediaCommand: Int, Equatable, Sendable, CaseIterable {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case nextTrack = 4
    case previousTrack = 5

    /// A stable name for this command in the accessibility tree.
    ///
    /// Lets a probe find and press a control by identity rather than by clicking coordinates,
    /// which is both flaky and unable to tell a working button from a dead one.
    public var accessibilityIdentifier: String {
        switch self {
        case .play: "media.play"
        case .pause: "media.pause"
        case .togglePlayPause: "media.toggle"
        case .nextTrack: "media.next"
        case .previousTrack: "media.previous"
        }
    }
}

/// Somewhere now-playing information comes from.
///
/// perch reads media state through a subprocess today, because macOS 15.4 put `MediaRemote`
/// behind an entitlement and the only working route is a helper loaded by an entitled `/usr/bin/
/// perl`. That is a loophole, and Apple may close it. This protocol is the seam: when that day
/// comes, only the conforming type changes.
public protocol MediaSource: AnyObject, Sendable {

    /// Updates as playback changes.
    ///
    /// `nil` means nothing is playing. The sequence finishes when the source stops.
    var updates: AsyncStream<NowPlaying?> { get }

    /// Begin producing updates. Calling twice is a no-op.
    func start()

    /// Stop and release everything. Calling twice is a no-op.
    func stop()

    /// Ask the current player to do something.
    func send(_ command: MediaCommand)
}
