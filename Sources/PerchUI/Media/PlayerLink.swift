import AppKit
import PerchCore

/// The app a track is coming from, and the way back to it.
///
/// The panel can start, stop, and seek, and that is the whole of what a transport does. Everything
/// else about what is playing — the queue, the album it came from, the lyrics — only exists in the
/// player's own window, so the panel needs a door to it rather than an ever-growing set of controls
/// that reimplement one badly.
///
/// Resolved through Launch Services rather than assumed: `bundleIdentifier` is whatever the system
/// says is emitting audio, and nothing guarantees a launchable app is behind it. A helper process,
/// an app that has since been deleted, or a player perch simply cannot reach all report an
/// identifier and resolve to nothing — which is the case that decides whether the artwork is a
/// button at all.
struct PlayerApp: Equatable, Sendable {

    /// Where the app is installed.
    let url: URL

    /// What to call it in a tooltip — "Spotify", not "com.spotify.client".
    let name: String

    /// Look up the app a bundle identifier names, or nil when nothing on this Mac claims it.
    ///
    /// Not free: this is a Launch Services query, so it belongs at the point the track changes and
    /// not in a `body` that is rebuilt twice a second by the scrubber's clock.
    @MainActor
    static func resolve(bundleIdentifier: String) -> PlayerApp? {
        guard !bundleIdentifier.isEmpty,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else { return nil }

        return PlayerApp(url: url, name: displayName(for: url))
    }

    /// The name the Finder shows, which is the one the user knows the app by.
    ///
    /// `displayName(atPath:)` respects both localisation and the user having renamed the app, and
    /// drops the `.app` extension the way every other part of the system does.
    static func displayName(for url: URL) -> String {
        let shown = FileManager.default.displayName(atPath: url.path)
        return shown.isEmpty ? url.deletingPathExtension().lastPathComponent : shown
    }

    /// Bring the player to the front, launching it if it is not running.
    ///
    /// `openApplication` rather than `NSRunningApplication.activate`: a player can report a track
    /// while sitting in the background, but it can also have been quit between the last update and
    /// this click, and only one of these two calls handles both.
    ///
    /// Activating another app is safe from here precisely because the panel never took focus —
    /// `NotchPanel` is non-activating, so the frontmost app changes to the player rather than to
    /// perch, which has no windows to show.
    @MainActor
    func open() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            guard let error else { return }
            Log.media.error("could not open \(name): \(error.localizedDescription)")
        }
    }
}
