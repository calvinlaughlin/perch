import Foundation
import PerchCore

/// Where the vendored adapter's two pieces live.
///
/// There are two of them and they are found separately: a Perl script, and a framework the script
/// loads. Both ship inside `perch.app`, but during development perch is often run from a build
/// directory instead, so both locations have to work or `make run` stops finding media.
public struct AdapterLocation: Equatable, Sendable {

    /// `mediaremote-adapter.pl`.
    public var script: URL

    /// `MediaRemoteAdapter.framework`.
    public var framework: URL

    public init(script: URL, framework: URL) {
        self.script = script
        self.framework = framework
    }

    /// Find the adapter, preferring the copy inside the running app bundle.
    ///
    /// Defaults to ``Bundle/running`` rather than `Bundle.main`: launched through the symlink the
    /// Homebrew cask puts on `PATH`, `Bundle.main` is `/opt/homebrew/bin` and has no `Resources`,
    /// so this would fall through to the development search, fail, and leave media unavailable.
    ///
    /// - Parameter bundle: the bundle to search; defaults to the running app.
    /// - Returns: the location, or nil if either piece is missing.
    public static func locate(in bundle: Bundle = .running) -> AdapterLocation? {
        if let script = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl"),
            let frameworks = bundle.privateFrameworksURL
        {
            let framework = frameworks.appendingPathComponent("MediaRemoteAdapter.framework")
            if FileManager.default.fileExists(atPath: framework.path) {
                return AdapterLocation(script: script, framework: framework)
            }
        }

        return developmentLocation()
    }

    /// Fall back to the build tree, for when perch is run outside an app bundle.
    ///
    /// Walks up from the executable looking for the repository layout. This is a development
    /// convenience only — a shipped perch always finds the bundled copy above.
    private static func developmentLocation() -> AdapterLocation? {
        var directory = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()

        for _ in 0..<6 {
            let script =
                directory
                .appendingPathComponent("Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl")
            let framework =
                directory
                .appendingPathComponent("build/adapter/MediaRemoteAdapter.framework")

            if FileManager.default.fileExists(atPath: script.path),
                FileManager.default.fileExists(atPath: framework.path)
            {
                return AdapterLocation(script: script, framework: framework)
            }
            directory = directory.deletingLastPathComponent()
        }

        return nil
    }
}
