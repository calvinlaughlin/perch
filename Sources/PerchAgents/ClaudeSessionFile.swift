import Foundation

/// Reading one of Claude Code's session files.
///
/// Claude Code keeps a directory of them, one per live session, named after the process id:
/// `~/.claude/sessions/70439.json`. Each holds the session's name, working directory, and current
/// status, and is rewritten whenever any of those change.
///
/// Nothing here is a documented interface, which is why every field is optional and a file that
/// cannot be understood is skipped rather than treated as an error. A future version that renames
/// something should cost perch an indicator, not a crash.
public enum ClaudeSessionFile {

    /// The directory the session files live in.
    ///
    /// `$CLAUDE_CONFIG_DIR/sessions` when that is set, otherwise `~/.claude/sessions` — the same
    /// resolution Claude Code itself does, so a person who has moved their config directory gets a
    /// working indicator rather than a permanently empty one.
    public static var directory: URL {
        let environment = ProcessInfo.processInfo.environment

        if let configured = environment["CLAUDE_CONFIG_DIR"], !configured.isEmpty {
            return URL(fileURLWithPath: configured, isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions", isDirectory: true)
    }

    /// The process id a session file is named after, or `nil` if the name is not one.
    ///
    /// The directory holds other things; only `<digits>.json` is a session.
    public static func pid(forFileNamed name: String) -> Int32? {
        guard name.hasSuffix(".json") else { return nil }

        let stem = name.dropLast(".json".count)
        guard !stem.isEmpty, stem.allSatisfy(\.isNumber) else { return nil }

        return Int32(stem)
    }

    /// Whether a process is still there.
    ///
    /// A session file outlives a session that crashed or was killed, so the file existing is not
    /// evidence the session does. `kill(pid, 0)` sends no signal and only reports whether the
    /// process can be signalled; `EPERM` means it exists but belongs to somebody else, which is
    /// still very much alive.
    public static func isRunning(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    /// Decode one session file.
    ///
    /// - Parameters:
    ///   - data: the file's contents.
    ///   - pid: taken from the file's *name* rather than its contents. The name is what the
    ///     liveness check is done against, and the two disagreeing would mean checking one process
    ///     and displaying another.
    /// - Returns: `nil` if the file is not a session perch should show.
    public static func decode(_ data: Data, pid: Int32) -> AgentSession? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }

        // Background sessions are shown; daemons and their workers are not. They are infrastructure
        // rather than something a person is waiting on, and they would sit in the strip permanently.
        switch payload.kind {
        case nil, "interactive", "bg": break
        default: return nil
        }

        return AgentSession(
            id: pid,
            name: payload.name,
            directory: payload.cwd,
            status: payload.status.map { AgentStatus(rawValue: $0) ?? .unknown } ?? .unknown,
            waitingFor: payload.waitingFor,
            startedAt: payload.startedAt.map {
                Date(timeIntervalSince1970: $0 / 1000)  // milliseconds, as JavaScript writes them
            }
        )
    }

    /// The subset of the file perch reads.
    ///
    /// Everything is optional because the file is written incrementally: it is created early and
    /// then updated in place, so a read can land between the two and see a session with no status
    /// yet.
    private struct Payload: Decodable {
        var name: String?
        var cwd: String?
        var status: String?
        var waitingFor: String?
        var kind: String?
        var startedAt: Double?
    }
}
