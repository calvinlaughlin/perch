import Foundation

extension Bundle {

    /// The bundle perch is actually running from.
    ///
    /// `Bundle.main` is derived from the path the executable was *launched* by, not from where it
    /// really lives. Homebrew's cask links the executable onto `PATH`, so running `perch` from a
    /// shell makes `Bundle.main` `/opt/homebrew/bin` — a directory with no `Info.plist` and no
    /// `Resources`. Everything read from the bundle then comes back nil: the version reads as
    /// `dev`, and `mediaremote-adapter.pl` cannot be found, which silently costs perch the media
    /// widget. Launching the same binary from Finder is fine, so it presents as "media works
    /// except when I start it from the terminal".
    ///
    /// Resolving the symlink first finds `perch.app` either way. Use this rather than
    /// `Bundle.main` for anything read out of the bundle.
    public static let running: Bundle = resolveRunning()

    /// Split out from ``running`` so the lazy `static let` stays a one-liner and this stays testable.
    static func resolveRunning(from candidate: Bundle = .main) -> Bundle {
        // Already a bundle with contents — launched normally, nothing to resolve.
        if candidate.infoDictionary?["CFBundleIdentifier"] != nil { return candidate }

        guard let executable = candidate.executableURL,
            let app = appBundleURL(containingExecutable: executable),
            let resolved = Bundle(url: app)
        else { return candidate }

        return resolved
    }

    /// The `.app` an executable lives inside, following symlinks.
    ///
    /// Matches the bundle layout exactly — `<name>.app/Contents/MacOS/<exe>` — rather than just
    /// walking up three levels, so an executable three directories below something coincidentally
    /// ending in `.app` is not mistaken for a bundle.
    ///
    /// - Returns: the `.app` URL, or nil if this executable is not inside one.
    public static func appBundleURL(containingExecutable executable: URL) -> URL? {
        let binary = executable.resolvingSymlinksInPath()

        let macOS = binary.deletingLastPathComponent()
        guard macOS.lastPathComponent == "MacOS" else { return nil }

        let contents = macOS.deletingLastPathComponent()
        guard contents.lastPathComponent == "Contents" else { return nil }

        let app = contents.deletingLastPathComponent()
        guard app.pathExtension == "app" else { return nil }

        return app
    }
}
