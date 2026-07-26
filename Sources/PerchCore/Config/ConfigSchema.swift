import CoreGraphics
import Foundation

/// One config key: how to spell it, what it accepts, what it does, and how to apply it.
public struct ConfigKey: Sendable {

    /// The key as written in the file.
    public let name: String

    /// What values are accepted, shown in help — `hover | click | never`, `points`, `duration`.
    public let syntax: String

    /// One-line explanation, shown by `perch --show-config --docs`.
    public let documentation: String

    /// Set this key on a config, or throw a `ConfigValueError` explaining why the value is no good.
    let apply: @Sendable (inout Config, String) throws -> Void

    /// Render this key's current value the way the file would spell it.
    let describe: @Sendable (Config) -> String
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
            syntax: OpenTrigger.allCases.map(\.rawValue).joined(separator: " | "),
            documentation: """
                What opens the notch. `never` leaves it inert to the pointer; widgets can still peek.
                """,
            apply: { $0.openOn = try ConfigValue.enumeration($1) },
            describe: { $0.openOn.rawValue }
        ),
        ConfigKey(
            name: "open-delay",
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
            name: "expanded-height",
            syntax: "points",
            documentation: "Height of the expanded panel below the notch.",
            apply: { $0.expandedHeight = try ConfigValue.length($1) },
            describe: { ConfigValue.describe($0.expandedHeight) }
        ),
        ConfigKey(
            name: "expanded-width",
            syntax: "points",
            documentation: "Width of the expanded panel. Clamped to the display width.",
            apply: { $0.expandedWidth = try ConfigValue.length($1) },
            describe: { ConfigValue.describe($0.expandedWidth) }
        ),
        ConfigKey(
            name: "corner-radius",
            syntax: "points",
            documentation: "Corner radius of the expanded panel's bottom corners.",
            apply: { $0.cornerRadius = try ConfigValue.length($1) },
            describe: { ConfigValue.describe($0.cornerRadius) }
        ),
        ConfigKey(
            name: "collapsed-corner-radius",
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
    /// This is what `perch --show-config` prints. Because it is generated from the same table the
    /// parser uses, it doubles as a reference that cannot go stale.
    public static func show(_ config: Config = Config(), includeDocs: Bool = false) -> String {
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
