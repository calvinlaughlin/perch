import Foundation

/// Where perch looks for its config file.
///
/// One canonical location, following the XDG convention that every other tool a developer already
/// has in `~/.config` uses. There is deliberately no search order and no per-machine override
/// file: a single path means the answer to "which config is running?" is never ambiguous.
public enum ConfigPaths {

    /// `$XDG_CONFIG_HOME/perch/config`, falling back to `~/.config/perch/config`.
    public static var configFile: URL {
        configDirectory.appendingPathComponent("config")
    }

    /// The directory the config file lives in.
    public static var configDirectory: URL {
        let environment = ProcessInfo.processInfo.environment

        // An empty XDG_CONFIG_HOME is treated as unset, which is what the spec says and what
        // people who export it conditionally in a shell profile expect.
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg, isDirectory: true)
                .appendingPathComponent("perch", isDirectory: true)
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/perch", isDirectory: true)
    }

    /// Create the config file if it does not exist, seeded with a short starter.
    ///
    /// Opening a genuinely empty file teaches nothing, but neither does a wall of commented-out
    /// settings — it reads as a form to fill in. The starter is a few lines that say the defaults
    /// are fine and name the command that lists every option.
    /// - Parameter contents: what to seed a missing file with. Supplied by the caller because it
    ///   is built in `PerchUI`, alongside the reference that documents the registered widgets.
    /// - Returns: the config file's location, whether it already existed or was just created.
    @discardableResult
    public static func ensureConfigFileExists(contents: @autoclosure () -> String) -> URL {
        let file = configFile
        guard !FileManager.default.fileExists(atPath: file.path) else { return file }

        try? FileManager.default.createDirectory(
            at: configDirectory, withIntermediateDirectories: true)
        try? contents().write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// A path with the home directory abbreviated, for logging.
    public static func display(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home)
            ? "~" + url.path.dropFirst(home.count)
            : url.path
    }
}
