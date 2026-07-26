import Foundation

/// One `key = value` line from a config file.
public struct ConfigAssignment: Equatable, Sendable {
    public var key: String

    /// The value as written, unquoted and trimmed.
    ///
    /// Empty means the line was `key =`, which resets that key to its default rather than setting
    /// it to an empty string. Nothing perch accepts is meaningfully empty, so the ambiguity costs
    /// nothing and the reset is worth having — it lets you neutralise a setting from an earlier
    /// file without deleting the line.
    public var value: String

    /// 1-based line number, for diagnostics.
    public var line: Int

    public init(key: String, value: String, line: Int) {
        self.key = key
        self.value = value
        self.line = line
    }

    /// Whether this line asks for the default rather than a specific value.
    public var isReset: Bool { value.isEmpty }
}

/// Turns config text into assignments.
///
/// The grammar is deliberately tiny — flat `key = value`, `#` comments, blank lines ignored — and
/// it has no nesting, no sections, and no types. Per-key namespacing is a naming convention
/// (`media-artwork`), not a syntax feature. One grammar means one set of rules to learn and one
/// place for parsing to go wrong.
public enum ConfigParser {

    /// Parse config text.
    ///
    /// Never throws: bad lines become diagnostics and are skipped.
    public static func parse(
        _ source: String,
        file: String? = nil
    ) -> (assignments: [ConfigAssignment], diagnostics: [Diagnostic]) {
        var assignments: [ConfigAssignment] = []
        var diagnostics: [Diagnostic] = []

        for (index, rawLine) in source.split(
            separator: "\n", omittingEmptySubsequences: false
        ).enumerated() {
            let number = index + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty || line.hasPrefix("#") { continue }

            guard let separator = line.firstIndex(of: "=") else {
                diagnostics.append(
                    Diagnostic(
                        severity: .warning,
                        line: number,
                        message: "expected 'key = value', found '\(line)'",
                        file: file
                    )
                )
                continue
            }

            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else {
                diagnostics.append(
                    Diagnostic(
                        severity: .warning,
                        line: number,
                        message: "missing key before '='",
                        file: file
                    )
                )
                continue
            }

            let rawValue = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)

            assignments.append(
                ConfigAssignment(key: key, value: unquote(rawValue), line: number)
            )
        }

        return (assignments, diagnostics)
    }

    /// Strip one layer of matching quotes.
    ///
    /// Quoting is optional and exists only so values can keep leading or trailing spaces, or a
    /// literal `#`. `font = "JetBrains Mono"` and `font = JetBrains Mono` mean the same thing.
    private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        let first = value.first
        guard first == "\"" || first == "'", value.last == first else { return value }
        return String(value.dropFirst().dropLast())
    }
}
