import Foundation
import PerchCore

/// Builds the annotated config file perch writes on first run.
///
/// **Everything is commented out.** A file that pinned every key at today's value would freeze
/// those values forever — a later perch that improves a default would never reach anyone who had
/// opened their config once. Commented lines document without pinning, so uncommenting is an
/// explicit "I disagree with this default" rather than an accident.
///
/// Lives in `PerchUI` rather than `PerchCore` because it lists the *registered* widgets and their
/// settings, and `PerchCore` has no idea widgets exist.
@MainActor
public enum ConfigTemplate {

    public static func starter(registry: WidgetRegistry = .shared) -> String {
        var out: [String] = [
            "# perch configuration",
            "#",
            "# Everything here is optional and everything is commented out, showing the default.",
            "# Uncomment a line to change it. Leaving one commented means you keep whatever perch's",
            "# default becomes in later versions, which is usually what you want.",
            "#",
            "# Saved changes apply immediately — no restart. A mistake is reported and skipped",
            "# rather than taken to heart, so a typo will not leave you without a notch.",
            "#",
            "# Full reference:  perch --show-config --docs",
        ]

        let defaults = Config()

        // Core keys, grouped, in schema order within each group.
        var seen = Set<String>()
        let order = ConfigSchema.keys.map(\.section).filter { seen.insert($0).inserted }

        for section in order {
            out.append("")
            out.append(heading(section))

            for key in ConfigSchema.keys where key.section == section {
                out.append("")
                for line in wrap(key.documentation, width: 92) { out.append("# \(line)") }
                out.append("# accepts: \(key.syntax)")
                out.append("#\(key.name) = \(key.describe(defaults))")
            }
        }

        // Widgets. The enabled ones are live rather than commented — a notch showing nothing is
        // not a useful first impression, and this is what perch does by default anyway.
        out.append("")
        out.append(heading("Widgets"))
        out.append("")
        for line in wrap(
            """
            Declared with a repeated key, drawn in the order listed. `widget =` with no value \
            clears the list. Each widget's settings are prefixed with its name.
            """, width: 92)
        {
            out.append("# \(line)")
        }

        for kind in registry.kinds {
            guard let description = registry.describe(kind) else { continue }
            let isDefault = defaults.widgets.contains(kind)

            out.append("")
            out.append("# \(kind) — \(description.summary)")
            if !isDefault {
                out.append("# Not enabled by default; uncomment to turn it on.")
            }
            out.append(isDefault ? "widget = \(kind)" : "#widget = \(kind)")

            for setting in description.settings {
                out.append("#")
                for line in wrap(setting.documentation, width: 90) { out.append("#   \(line)") }
                out.append("#   accepts: \(setting.syntax)")
                out.append("#\(kind)-\(setting.name) = \(setting.defaultValue)")
            }
        }

        return out.joined(separator: "\n") + "\n"
    }

    private static func heading(_ title: String) -> String {
        let rule = String(repeating: "─", count: max(0, 76 - title.count))
        return "# ── \(title) \(rule)"
    }

    /// Greedy word wrap, so the generated file stays readable in a narrow editor.
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
