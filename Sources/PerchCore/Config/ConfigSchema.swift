import CoreGraphics
import Foundation

/// One config key: how to spell it, what it accepts, what it does, and how to apply it.
public struct ConfigKey: Sendable {

    /// The key as written in the file.
    public let name: String

    /// Which heading this key appears under in a generated config file.
    public let section: String

    /// What values are accepted, shown in help — `hover | click | never`, `points`, `duration`.
    public let syntax: String

    /// One-line explanation, shown by `perch +show-config --docs`.
    public let documentation: String

    /// Set this key on a config, or throw a `ConfigValueError` explaining why the value is no good.
    let apply: @Sendable (inout Config, String) throws -> Void

    /// Render this key's current value the way the file would spell it.
    public let describe: @Sendable (Config) -> String
}

/// The complete set of keys perch understands.
///
/// This table and the `Config` struct are the schema between them: the struct declares the
/// defaults and documents each field, the table says how each one is spelled and parsed. Adding a
/// setting means touching both, which is the point — a field with no entry here is unreachable,
/// and an entry here with no field does not compile.
///
/// Defaults are never written down twice. `describe` reads them off a default-constructed `Config`,
/// so the help output cannot drift away from what the code actually does.
public enum ConfigSchema {

    public static let keys: [ConfigKey] = [
        ConfigKey(
            name: "open-on",
            section: "Interaction",
            syntax: OpenTrigger.allCases.map(\.rawValue).joined(separator: " | "),
            documentation: """
                What opens the notch. `never` leaves it inert to the pointer; widgets can still peek.
                """,
            apply: { $0.openOn = try ConfigValue.enumeration($1) },
            describe: { $0.openOn.rawValue }
        ),
        ConfigKey(
            name: "open-delay",
            section: "Interaction",
            syntax: "duration",
            documentation: """
                How long the pointer must rest on the notch before it opens. Stops the notch flying \
                open every time the pointer crosses the top of the screen. Ignored unless \
                `open-on` is `hover`.
                """,
            apply: { $0.openDelay = try ConfigValue.duration($1) },
            describe: { ConfigValue.describe($0.openDelay) }
        ),
        ConfigKey(
            name: "haptics",
            section: "Interaction",
            syntax: HapticTrigger.allCases.map(\.rawValue).joined(separator: " | "),
            documentation: """
                Which events tap the trackpad. `open` taps when the notch opens, `peek` when a \
                widget announces something, `all` for both. Needs a Force Touch trackpad and \
                system haptics left on; does nothing otherwise.
                """,
            apply: { $0.haptics = try ConfigValue.enumeration($1) },
            describe: { $0.haptics.rawValue }
        ),
        ConfigKey(
            name: "haptic-pattern",
            section: "Interaction",
            syntax: HapticPattern.allCases.map(\.rawValue).joined(separator: " | "),
            documentation: """
                How a tap feels. `alignment` is the light tap of something snapping to a guide, \
                `generic` a single firmer one, `level-change` the two-part tap of a detent. \
                Ignored unless `haptics` is on.
                """,
            apply: { $0.hapticPattern = try ConfigValue.enumeration($1) },
            describe: { $0.hapticPattern.rawValue }
        ),
        ConfigKey(
            name: "display",
            section: "Display",
            syntax: "notched | main | <display name>",
            documentation: """
                Which display perch lives on. `notched` prefers one with a camera housing, `main` \
                follows the menu bar, and anything else matches a display name. Falls back to \
                `notched` if the named display is not connected.
                """,
            apply: { $0.display = $1 },
            describe: { $0.display }
        ),
        ConfigKey(
            name: "expanded-height",
            section: "Shape",
            syntax: "points",
            documentation: "Height of the expanded panel below the notch.",
            apply: { $0.expandedHeight = try ConfigValue.length($1) },
            describe: { ConfigValue.describe($0.expandedHeight) }
        ),
        ConfigKey(
            name: "expanded-width",
            section: "Shape",
            syntax: "points",
            documentation: "Width of the expanded panel. Clamped to the display width.",
            apply: { $0.expandedWidth = try ConfigValue.length($1) },
            describe: { ConfigValue.describe($0.expandedWidth) }
        ),
        ConfigKey(
            name: "peek-height",
            section: "Announcements",
            syntax: "points",
            documentation: """
                Height of the panel shown when a widget announces something. Smaller than \
                `expanded-height` on purpose: a peek is glanced at, not interacted with.
                """,
            apply: { $0.peekHeight = try ConfigValue.length($1) },
            describe: { ConfigValue.describe($0.peekHeight) }
        ),
        ConfigKey(
            name: "peek-duration",
            section: "Announcements",
            syntax: "duration",
            documentation: "How long an announcement stays up before reverting on its own.",
            apply: { $0.peekDuration = try ConfigValue.duration($1) },
            describe: { ConfigValue.describe($0.peekDuration) }
        ),
        ConfigKey(
            name: "peek-on-track-change",
            section: "Announcements",
            syntax: "true | false",
            documentation: "Whether changing track makes the notch announce the new one.",
            apply: { $0.peekOnTrackChange = try ConfigValue.bool($1) },
            describe: { $0.peekOnTrackChange ? "true" : "false" }
        ),
        ConfigKey(
            name: "expanded-scroll",
            section: "Interaction",
            syntax: ExpandedScroll.allCases.map(\.rawValue).joined(separator: " | "),
            documentation: """
                What scrolling does past the last widget in the expanded panel. `endless` carries \
                on into the first; `rewind` travels back across the deck to reach it.
                """,
            apply: { $0.expandedScroll = try ConfigValue.enumeration($1) },
            describe: { $0.expandedScroll.rawValue }
        ),
        ConfigKey(
            name: "corner-radius",
            section: "Shape",
            syntax: "points",
            documentation: "Corner radius of the expanded panel's bottom corners.",
            apply: { $0.cornerRadius = try ConfigValue.length($1) },
            describe: { ConfigValue.describe($0.cornerRadius) }
        ),
        ConfigKey(
            name: "collapsed-corner-radius",
            section: "Shape",
            syntax: "points",
            documentation: """
                Corner radius of the collapsed shape's bottom corners. Defaults to roughly the \
                curvature of the camera housing, so the collapsed state disappears into it.
                """,
            apply: { $0.collapsedCornerRadius = try ConfigValue.length($1) },
            describe: { ConfigValue.describe($0.collapsedCornerRadius) }
        ),
        ConfigKey(
            name: "collapsed-bleed",
            section: "Shape",
            syntax: "points",
            documentation: """
                Extra width added to each side of the collapsed shape, letting widgets spill into \
                the dead space beside the camera housing. Zero traces the hardware exactly.
                """,
            apply: { $0.collapsedBleed = try ConfigValue.length($1) },
            describe: { ConfigValue.describe($0.collapsedBleed) }
        ),
        ConfigKey(
            name: "shoulder-radius",
            section: "Shape",
            syntax: "points",
            documentation: """
                Radius of the concave shoulders where an open panel meets the top of the display. \
                Suppressed automatically while the shape is tracing the camera housing.
                """,
            apply: { $0.shoulderRadius = try ConfigValue.length($1) },
            describe: { ConfigValue.describe($0.shoulderRadius) }
        ),
        ConfigKey(
            name: "debug-shape",
            section: "Debugging",
            syntax: "true | false",
            documentation: """
                Draw the notch tinted and outlined instead of black, so its geometry is visible \
                against the hardware.
                """,
            apply: { $0.debugShape = try ConfigValue.bool($1) },
            describe: { $0.debugShape ? "true" : "false" }
        ),
    ]

    private static let byName: [String: ConfigKey] = Dictionary(
        uniqueKeysWithValues: keys.map { ($0.name, $0) }
    )

    /// Look up a key by its spelling in the file.
    public static func key(named name: String) -> ConfigKey? { byName[name] }

    /// Render a config the way a file would spell it, optionally with the documentation.
    ///
    /// This is what `perch +show-config` prints. Because it is generated from the same table the
    /// parser uses, it doubles as a reference that cannot go stale — and since the config perch
    /// writes on first run is deliberately almost empty, this is where every option is documented.
    ///
    /// The output is itself a valid config file that reproduces `config`. That is why a widget
    /// that is not enabled has its settings commented out: a bare `clock-24-hour` with no
    /// `widget = clock` above it is a warning, not a setting, so printing it live would make the
    /// output a file perch itself would complain about.
    ///
    /// - Parameters:
    ///   - config: the config to render.
    ///   - includeDocs: whether to precede each key with its documentation.
    ///   - widgets: the registered widgets to document, supplied by `PerchUI`. Empty here prints
    ///     core keys only, which is all `PerchCore` can know about on its own.
    /// - Returns: the config as file text, loadable back into an equal `Config`.
    public static func show(
        _ config: Config = Config(),
        includeDocs: Bool = false,
        widgets: [WidgetDocumentation] = []
    ) -> String {
        var lines: [String] = []
        for key in keys {
            if includeDocs {
                if !lines.isEmpty { lines.append("") }
                for line in wrap(key.documentation, width: 92) {
                    lines.append("# \(line)")
                }
                lines.append("# accepts: \(key.syntax)")
            }
            lines.append("\(key.name) = \(key.describe(config))")
        }

        // Enabled widgets first, in the order the config lists them, because that is the order
        // they are drawn in — printing them in registry order would round-trip to a different
        // layout. Disabled ones follow, in registry order, as a menu of what else exists.
        let enabledFirst =
            config.widgets.compactMap { kind in widgets.first { $0.kind == kind } }
            + widgets.filter { !config.widgets.contains($0.kind) }

        // `widget = <kind>` adds to the default list rather than replacing it, so printing the
        // enabled ones alone would reproduce this config plus whatever perch defaults to. The
        // empty `widget =` resets the list first, making the output say exactly what it means —
        // and keeping it correct if the default list changes in a later version.
        //
        // Only when every enabled widget is documented here: if the caller passed a partial
        // registry, clearing the list would drop the ones it did not describe.
        let canResetList =
            !widgets.isEmpty
            && config.widgets.allSatisfy { kind in
                widgets.contains { $0.kind == kind }
            }
        if canResetList {
            lines.append("")
            lines.append("widget =")
        }

        for widget in enabledFirst {
            let enabled = config.widgets.contains(widget.kind)
            // A disabled widget's lines are commented so the output stays loadable; an enabled
            // one's are live so re-loading the output gives the config back unchanged.
            let prefix = enabled ? "" : "#"

            lines.append("")
            if includeDocs {
                lines.append("# \(widget.kind) — \(widget.summary)")
            }
            lines.append("\(prefix)widget = \(widget.kind)")

            let settings = config.settings(for: widget.kind)
            for setting in widget.settings {
                if includeDocs {
                    lines.append("#")
                    for line in wrap(setting.documentation, width: 90) {
                        lines.append("#   \(line)")
                    }
                    lines.append("#   accepts: \(setting.syntax)")
                }
                let value = settings.string(setting.name, default: setting.defaultValue)
                lines.append("\(prefix)\(widget.kind)-\(setting.name) = \(value)")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Greedy word wrap, so generated documentation stays readable in a terminal.
    private static func wrap(_ text: String, width: Int) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ") {
            if current.isEmpty {
                current = String(word)
            } else if current.count + 1 + word.count <= width {
                current += " \(word)"
            } else {
                lines.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }
}
