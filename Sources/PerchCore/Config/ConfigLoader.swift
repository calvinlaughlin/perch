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

        for assignment in assignments {
            guard let key = ConfigSchema.key(named: assignment.key) else {
                diagnostics.append(
                    Diagnostic(
                        severity: .warning,
                        line: assignment.line,
                        message: unknownKeyMessage(assignment.key),
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

    /// Suggest a real key when someone nearly typed one.
    ///
    /// Config keys are typed from memory and hyphenated, which makes near-misses the common case
    /// rather than the exotic one. "did you mean" turns a silent no-op into a one-second fix.
    private static func unknownKeyMessage(_ typed: String) -> String {
        let suggestion =
            ConfigSchema.keys
            .map { ($0.name, editDistance(typed, $0.name)) }
            .filter { $0.1 <= max(2, typed.count / 3) }
            .min { $0.1 < $1.1 }?
            .0

        guard let suggestion else { return "unknown key '\(typed)'" }
        return "unknown key '\(typed)' — did you mean '\(suggestion)'?"
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
