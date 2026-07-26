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

    /// A path with the home directory abbreviated, for logging.
    public static func display(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home)
            ? "~" + url.path.dropFirst(home.count)
            : url.path
    }
}
