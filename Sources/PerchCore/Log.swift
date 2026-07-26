import Foundation
import OSLog

/// A named logging channel.
///
/// Wraps `os.Logger` so call sites read as `Log.config.error(...)` rather than repeating the
/// subsystem string everywhere. Errors additionally go to stderr: perch is a tool you configure
/// by editing a file, and "your config has a typo on line 12" is useless if the only way to see
/// it is `log stream`.
public struct Log: Sendable {

    private static let subsystem = "dev.perch.perch"

    private let logger: Logger
    private let label: String

    private init(category: String) {
        self.logger = Logger(subsystem: Self.subsystem, category: category)
        self.label = category
    }

    /// Detail useful while developing; compiled out of release logging by the system.
    public func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    /// Ordinary lifecycle events worth keeping in the system log.
    public func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    /// A problem the user can act on.
    ///
    /// Mirrored to stderr so it is visible when perch is run from a terminal, which is how it is
    /// run while someone is iterating on their config.
    public func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        FileHandle.standardError.write(Data("perch: \(label): \(message)\n".utf8))
    }

    /// Config parsing, validation, and reload.
    public static let config = Log(category: "config")

    /// Display detection and notch geometry.
    public static let geometry = Log(category: "geometry")

    /// Widget lifecycle and rendering.
    public static let widget = Log(category: "widget")

    /// Now-playing sources and playback control.
    public static let media = Log(category: "media")
}
