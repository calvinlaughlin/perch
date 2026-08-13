import Foundation

/// What a coding-agent session is doing.
///
/// These are Claude Code's own words, read verbatim from the file it publishes. `unknown` is not
/// one of them: it is what perch records when a future version reports a status this build has
/// never heard of. That case is the whole reason the enum is not `Optional` — an unrecognised
/// status has to be inert, because the alternative is deciding it looks enough like `idle` to
/// announce, and then announcing a session that has not finished anything.
public enum AgentStatus: String, Equatable, Sendable, CaseIterable {

    /// Working on a turn.
    case busy

    /// Running a foreground shell.
    case shell

    /// Blocked on the person — a permission prompt, a dialog, an answer it asked for.
    case waiting

    /// At the prompt with nothing to do.
    case idle

    /// Something this build does not recognise.
    case unknown

    /// Whether the session is doing work rather than waiting on anybody.
    ///
    /// `shell` counts: the session is mid-turn, running a command. Treating it as finished would
    /// announce every `git status` as a completed turn.
    public var isWorking: Bool { self == .busy || self == .shell }
}

/// One live coding-agent session.
///
/// Deliberately carries no `updatedAt`, though the file has one. The session file is rewritten
/// whenever anything at all changes, and a timestamp that moves every time would make every
/// snapshot unequal to the last — so the widget would redraw, and the peek logic would re-run, for
/// writes that changed nothing anyone can see. Leaving it out is what makes `Equatable` here mean
/// "differs in a way worth reacting to".
public struct AgentSession: Equatable, Sendable, Identifiable {

    /// The session's process id, which is also the name of the file it was read from.
    public let id: Int32

    /// A short label the agent chose for itself, e.g. `perch-af`.
    public let name: String?

    /// The directory the session is working in.
    public let directory: String?

    public let status: AgentStatus

    /// What a `waiting` session is blocked on, e.g. `input needed`.
    public let waitingFor: String?

    /// When the session started, used only to keep the running order stable.
    public let startedAt: Date?

    public init(
        id: Int32,
        name: String? = nil,
        directory: String? = nil,
        status: AgentStatus,
        waitingFor: String? = nil,
        startedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.directory = directory
        self.status = status
        self.waitingFor = waitingFor
        self.startedAt = startedAt
    }

    /// The best short name for this session.
    ///
    /// Falls back through the directory to the pid, because the label is read at a glance in a
    /// strip a few points wide and "session 70439" is still more use than an empty space.
    public var label: String {
        if let name, !name.isEmpty { return name }

        if let directory, !directory.isEmpty {
            let leaf = URL(fileURLWithPath: directory).lastPathComponent
            if !leaf.isEmpty, leaf != "/" { return leaf }
        }

        return "session \(id)"
    }
}
