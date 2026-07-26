import Foundation

/// The result of reading a config: what perch should use, and everything wrong with the file.
public struct ConfigLoadResult: Sendable {
    public var config: Config
    public var diagnostics: [Diagnostic]

    public var hasProblems: Bool { !diagnostics.isEmpty }
}

/// Reads config text and files into a `Config`.
///
/// Loading is total — it always produces a usable config. A key that is misspelled, or given a
/// value it cannot accept, is reported and skipped while everything else applies. That matters
/// because this file gets reloaded as you save it: a strict loader would leave you staring at a
/// broken notch every time you typed a character in the wrong place.
public enum ConfigLoader {

    /// Load from text, starting from the defaults.
    public static func load(source: String, file: String? = nil) -> ConfigLoadResult {
        var config = Config()
        let defaults = Config()

        let (assignments, parseDiagnostics) = ConfigParser.parse(source, file: file)
        var diagnostics = parseDiagnostics

        // Widgets are declared before their settings can be routed, and a `media-artwork` line is
        // allowed to appear above the `widget = media` that gives it meaning — people group
        // settings by topic, not by declaration order. So collect the declarations first.
        for assignment in assignments where assignment.key == Self.widgetKey {
            if assignment.isReset {
                config.widgets.removeAll()
            } else if !config.widgets.contains(assignment.value) {
                config.widgets.append(assignment.value)
            }
        }

        for assignment in assignments {
            if assignment.key == Self.widgetKey { continue }  // already handled

            // A key prefixed with a declared widget's kind belongs to that widget.
            if let (kind, setting) = Self.widgetSetting(assignment.key, declared: config.widgets) {
                if assignment.isReset {
                    config.widgetSettings[kind]?.removeValue(forKey: setting)
                } else {
                    config.widgetSettings[kind, default: [:]][setting] = assignment.value
                }
                continue
            }

            guard let key = ConfigSchema.key(named: assignment.key) else {
                diagnostics.append(
                    Diagnostic(
                        severity: .warning,
                        line: assignment.line,
                        message: unknownKeyMessage(assignment.key, widgets: config.widgets),
                        file: file
                    )
                )
                continue
            }

            // `key =` means "whatever the default is", which lets a later file neutralise an
            // earlier one without the reader having to know what the default was.
            if assignment.isReset {
                try? key.apply(&config, key.describe(defaults))
                continue
            }

            do {
                try key.apply(&config, assignment.value)
            } catch let error as ConfigValueError {
                diagnostics.append(
                    Diagnostic(
                        severity: .warning,
                        line: assignment.line,
                        message: "\(assignment.key): \(error.message)",
                        file: file
                    )
                )
            } catch {
                diagnostics.append(
                    Diagnostic(
                        severity: .warning,
                        line: assignment.line,
                        message: "\(assignment.key): \(error)",
                        file: file
                    )
                )
            }
        }

        return ConfigLoadResult(config: config, diagnostics: diagnostics)
    }

    /// Load from a file.
    ///
    /// A missing file is not a problem — perch is meant to work without one.
    public static func load(contentsOf url: URL) -> ConfigLoadResult {
        let path = url.path

        guard FileManager.default.fileExists(atPath: path) else {
            return ConfigLoadResult(config: Config(), diagnostics: [])
        }

        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            return load(source: source, file: path)
        } catch {
            return ConfigLoadResult(
                config: Config(),
                diagnostics: [
                    Diagnostic(
                        severity: .error,
                        message: "could not read config: \(error.localizedDescription)",
                        file: path
                    )
                ]
            )
        }
    }

    /// The repeated key that declares a widget.
    private static let widgetKey = "widget"

    /// Split `media-artwork` into `("media", "artwork")`, if `media` is a declared widget.
    ///
    /// Matching only against *declared* widgets is what lets settings live in a flat namespace
    /// without a registry: the file says which prefixes are widgets, so a stray `media-artwork`
    /// with no `widget = media` above it is still reported as the mistake it is.
    ///
    /// Longest prefix wins, so a widget named `media-remote` beats one named `media`.
    private static func widgetSetting(
        _ key: String,
        declared widgets: [String]
    ) -> (kind: String, setting: String)? {
        widgets
            .filter { key.hasPrefix("\($0)-") && key.count > $0.count + 1 }
            .max { $0.count < $1.count }
            .map { (kind: $0, setting: String(key.dropFirst($0.count + 1))) }
    }

    /// Suggest a real key when someone nearly typed one.
    ///
    /// Config keys are typed from memory and hyphenated, which makes near-misses the common case
    /// rather than the exotic one. "did you mean" turns a silent no-op into a one-second fix.
    private static func unknownKeyMessage(_ typed: String, widgets: [String]) -> String {
        // A prefixed key with no matching declaration is nearly always a missing `widget =` line
        // rather than a typo, and saying so is more useful than guessing at a spelling.
        if let prefix = typed.split(separator: "-").first, typed.contains("-"),
            !widgets.contains(String(prefix))
        {
            let candidates = ConfigSchema.keys.map(\.name)
            if !candidates.contains(typed), editDistance(typed, closest(to: typed) ?? "") > 2 {
                return """
                    unknown key '\(typed)' — if this is a widget setting, declare the widget first \
                    with 'widget = \(prefix)'
                    """
            }
        }

        guard let suggestion = closest(to: typed) else { return "unknown key '\(typed)'" }
        return "unknown key '\(typed)' — did you mean '\(suggestion)'?"
    }

    /// The nearest real key, when one is near enough to be worth suggesting.
    private static func closest(to typed: String) -> String? {
        ConfigSchema.keys
            .map { ($0.name, editDistance(typed, $0.name)) }
            .filter { $0.1 <= max(2, typed.count / 3) }
            .min { $0.1 < $1.1 }?
            .0
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a)
        let b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }

        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
