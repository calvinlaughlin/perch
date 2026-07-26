import CoreGraphics
import Foundation

/// Where a widget is drawn.
public enum Placement: String, Equatable, Sendable, CaseIterable {
    /// In the strip left of the camera housing, visible while collapsed.
    case leading

    /// In the strip right of the camera housing, visible while collapsed.
    case trailing

    /// In the body of the panel, visible only when open.
    case expanded
}

/// One documented setting a widget accepts.
///
/// Lets a widget describe its own options so the starter config can list them. Without this the
/// only way to discover `media-artwork` would be to read the source, which rather defeats a
/// config file whose whole premise is that it explains itself.
public struct WidgetSetting: Equatable, Sendable {
    /// The name after the widget's prefix: `artwork` in `media-artwork`.
    public let name: String

    /// What values are accepted, e.g. `true | false`.
    public let syntax: String

    /// The value used when the setting is absent.
    public let defaultValue: String

    /// One line explaining what it does.
    public let documentation: String

    public init(name: String, syntax: String, defaultValue: String, documentation: String) {
        self.name = name
        self.syntax = syntax
        self.defaultValue = defaultValue
        self.documentation = documentation
    }
}

/// One widget's settings, as written in the config file.
///
/// Values arrive as strings and are parsed by the widget itself. That keeps `PerchCore` from
/// needing to know every setting every widget will ever have, and it means adding a widget is a
/// new file rather than an edit to the config schema.
///
/// Accessors take a default and never throw for a missing key: a widget must be usable with no
/// settings at all, exactly like perch itself.
public struct WidgetSettings: Equatable, Sendable {

    /// The widget kind these belong to, e.g. `media`.
    public let kind: String

    private let values: [String: String]

    public init(kind: String, values: [String: String] = [:]) {
        self.kind = kind
        self.values = values
    }

    /// Every setting name present, for diagnostics about unrecognised ones.
    public var names: Set<String> { Set(values.keys) }

    public func string(_ name: String, default fallback: String) -> String {
        values[name] ?? fallback
    }

    public func bool(_ name: String, default fallback: Bool) throws -> Bool {
        guard let raw = values[name] else { return fallback }
        return try prefixed(name) { try ConfigValue.bool(raw) }
    }

    public func length(_ name: String, default fallback: CGFloat) throws -> CGFloat {
        guard let raw = values[name] else { return fallback }
        return try prefixed(name) { try ConfigValue.length(raw) }
    }

    public func duration(_ name: String, default fallback: Duration) throws -> Duration {
        guard let raw = values[name] else { return fallback }
        return try prefixed(name) { try ConfigValue.duration(raw) }
    }

    public func enumeration<T>(_ name: String, default fallback: T) throws -> T
    where T: RawRepresentable & CaseIterable, T.RawValue == String {
        guard let raw = values[name] else { return fallback }
        return try prefixed(name) { try ConfigValue.enumeration(raw, as: T.self) }
    }

    /// Restate a parse failure using the key as the user wrote it.
    ///
    /// Without this the message would name the bare setting (`artwork`) rather than the key in the
    /// file (`media-artwork`), which is not something the reader can search for.
    private func prefixed<T>(_ name: String, _ parse: () throws -> T) throws -> T {
        do {
            return try parse()
        } catch let error as ConfigValueError {
            throw ConfigValueError("\(kind)-\(name): \(error.message)")
        }
    }
}
