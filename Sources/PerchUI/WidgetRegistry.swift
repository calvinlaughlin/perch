import PerchCore
import SwiftUI

/// Maps the names used in the config file to widget types.
///
/// A registry rather than a hard-coded switch so that adding a widget touches one file plus one
/// registration line, and so the set of known kinds can be enumerated — which is what lets an
/// unrecognised `widget = wibble` produce a diagnostic listing what does exist.
@MainActor
public final class WidgetRegistry {

    public static let shared = WidgetRegistry()

    private var factories: [String: (WidgetSettings) throws -> any NotchWidget] = [:]

    public init() {}

    /// Register a widget type under its `kind`.
    public func register<W: NotchWidget>(_ type: W.Type) {
        factories[type.kind] = { try type.init(settings: $0) }
    }

    /// Every registered kind, sorted, for diagnostics and help.
    public var kinds: [String] { factories.keys.sorted() }

    public func isRegistered(_ kind: String) -> Bool { factories[kind] != nil }

    /// Build one widget.
    ///
    /// - Throws: whatever the widget's initialiser throws, typically a `ConfigValueError`.
    /// - Returns: `nil` if no widget of that kind is registered.
    public func make(kind: String, settings: WidgetSettings) throws -> (any NotchWidget)? {
        try factories[kind]?(settings)
    }

    /// Build every widget a config asks for, collecting problems rather than failing.
    ///
    /// A config naming a widget that does not exist, or configuring one badly, must not stop the
    /// others from loading — same rule as the rest of the config system.
    public func makeAll(
        for config: Config
    ) -> (widgets: [any NotchWidget], diagnostics: [Diagnostic]) {
        var widgets: [any NotchWidget] = []
        var diagnostics: [Diagnostic] = []

        for kind in config.widgets {
            guard isRegistered(kind) else {
                diagnostics.append(
                    Diagnostic(
                        severity: .warning,
                        message:
                            "unknown widget '\(kind)' — available: \(kinds.joined(separator: ", "))"
                    )
                )
                continue
            }

            do {
                if let widget = try make(kind: kind, settings: config.settings(for: kind)) {
                    widgets.append(widget)
                }
            } catch let error as ConfigValueError {
                diagnostics.append(Diagnostic(severity: .warning, message: error.message))
            } catch {
                diagnostics.append(
                    Diagnostic(severity: .warning, message: "widget '\(kind)': \(error)")
                )
            }
        }

        return (widgets, diagnostics)
    }
}
