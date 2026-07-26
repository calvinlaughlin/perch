import Foundation

/// Something wrong with a config file, reported the way a compiler would.
///
/// Diagnostics never abort a load. A config file is something the user edits by hand while perch
/// is running, so it will be malformed regularly and briefly — mid-keystroke, mid-paste. Refusing
/// to start, or dropping every other setting because one line has a typo, would make the file
/// hostile to edit. Bad lines are reported and skipped; everything else still applies.
public struct Diagnostic: Equatable, Sendable {

    public enum Severity: String, Equatable, Sendable {
        /// The line was skipped; the rest of the file still applies.
        case warning
        /// The file could not be read at all.
        case error
    }

    public var severity: Severity

    /// 1-based line number, or `nil` when the problem is with the file rather than a line in it.
    public var line: Int?

    public var message: String

    /// Path of the file this came from, when it came from one.
    public var file: String?

    public init(severity: Severity, line: Int? = nil, message: String, file: String? = nil) {
        self.severity = severity
        self.line = line
        self.message = message
        self.file = file
    }

    /// `path:line: warning: message` — the shape every editor and terminal already knows how to
    /// parse, so jumping to the offending line works without perch doing anything clever.
    public var description: String {
        var location = file ?? "config"
        if let line { location += ":\(line)" }
        return "\(location): \(severity.rawValue): \(message)"
    }
}
