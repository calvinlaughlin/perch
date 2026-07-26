import CoreGraphics
import Foundation

/// A value that could not be understood, carrying a message aimed at the person editing the file.
public struct ConfigValueError: Error, Equatable, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
}

/// Parsers for the handful of value shapes perch accepts.
///
/// Every failure explains what was expected rather than just what was wrong, because the reader is
/// someone editing a text file, not someone debugging perch.
public enum ConfigValue {

    /// `true`/`false`, plus the spellings people reach for anyway.
    public static func bool(_ text: String) throws -> Bool {
        switch text.lowercased() {
        case "true", "yes", "on", "1": true
        case "false", "no", "off", "0": false
        default:
            throw ConfigValueError("expected true or false, found '\(text)'")
        }
    }

    /// A non-negative length in points.
    public static func length(_ text: String) throws -> CGFloat {
        guard let value = Double(text), value.isFinite else {
            throw ConfigValueError("expected a number of points, found '\(text)'")
        }
        guard value >= 0 else {
            throw ConfigValueError("expected a length of zero or more, found '\(text)'")
        }
        return CGFloat(value)
    }

    /// A duration: `120ms`, `1.5s`, or a bare number read as milliseconds.
    ///
    /// Milliseconds is the bare unit because every duration perch has is an interaction delay, and
    /// those are naturally written in the tens and hundreds.
    public static func duration(_ text: String) throws -> Duration {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        func milliseconds(_ amount: Double) throws -> Duration {
            guard amount.isFinite, amount >= 0 else {
                throw ConfigValueError("expected a duration of zero or more, found '\(text)'")
            }
            return .milliseconds(Int(amount.rounded()))
        }

        if trimmed.hasSuffix("ms"), let amount = Double(trimmed.dropLast(2)) {
            return try milliseconds(amount)
        }
        if trimmed.hasSuffix("s"), let amount = Double(trimmed.dropLast(1)) {
            return try milliseconds(amount * 1000)
        }
        if let amount = Double(trimmed) {
            return try milliseconds(amount)
        }
        throw ConfigValueError("expected a duration like 120ms or 1.5s, found '\(text)'")
    }

    /// One of an enum's cases, matched by its spelling in the file.
    public static func enumeration<T>(_ text: String, as type: T.Type = T.self) throws -> T
    where T: RawRepresentable & CaseIterable, T.RawValue == String {
        guard let value = T(rawValue: text.lowercased()) else {
            let options = T.allCases.map(\.rawValue).joined(separator: ", ")
            throw ConfigValueError("expected one of: \(options) — found '\(text)'")
        }
        return value
    }

    /// Render a duration the way the config file would spell it.
    ///
    /// Whole seconds are written as seconds. `2s` is what someone would type and what the
    /// documentation says; `2000ms` is the same value spelled in a way nobody chooses.
    public static func describe(_ duration: Duration) -> String {
        let ms =
            duration.components.seconds * 1000
            + duration.components.attoseconds / 1_000_000_000_000_000
        if ms >= 1000, ms % 1000 == 0 { return "\(ms / 1000)s" }
        return "\(ms)ms"
    }

    /// Render a length without a pointless trailing `.0`.
    public static func describe(_ length: CGFloat) -> String {
        length == length.rounded()
            ? String(Int(length))
            : String(format: "%g", Double(length))
    }
}
