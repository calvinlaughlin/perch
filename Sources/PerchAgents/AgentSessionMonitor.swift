import Foundation

/// Which session changes are worth interrupting for.
public enum AgentAnnouncePolicy: String, Equatable, Sendable, CaseIterable {

    /// A session finishing, and a session blocking on you.
    case all

    /// Only a session finishing its turn.
    case finished

    /// Only a session blocked on you.
    case waiting

    /// Never announce; the indicator still updates.
    case never
}

/// Something that happened to a session and is worth saying out loud.
public struct AgentAnnouncement: Equatable, Sendable {

    public enum Kind: Equatable, Sendable {
        /// Was working, now is not. The "they're done" case.
        case finished

        /// Has stopped and is blocked on the person.
        case needsYou
    }

    public let kind: Kind
    public let session: AgentSession

    public init(kind: Kind, session: AgentSession) {
        self.kind = kind
        self.session = session
    }
}

/// Turns successive observations of the running sessions into announcements.
///
/// Pure and synchronous, like `NotchStateMachine`, and for the same reason: every rule about what
/// deserves to interrupt somebody can then be tested by feeding it two arrays, with no filesystem,
/// no clock, and no display.
public struct AgentSessionMonitor: Equatable, Sendable {

    public var policy: AgentAnnouncePolicy

    /// The status each session had when it was last seen.
    private var previous: [Int32: AgentStatus] = [:]

    /// Whether any observation has been made yet.
    ///
    /// The first one is a baseline and announces nothing. Without it, starting perch while three
    /// sessions sat finished would announce all three — news to nobody, since they finished before
    /// perch was watching. The same reset happens when the display wakes, so a lid opening does not
    /// replay everything that happened while it was shut.
    private var hasBaseline = false

    public init(policy: AgentAnnouncePolicy = .all) {
        self.policy = policy
    }

    /// Record what the sessions look like now.
    ///
    /// - Returns: what changed that is worth announcing, most urgent first.
    public mutating func observe(_ sessions: [AgentSession]) -> [AgentAnnouncement] {
        defer {
            previous = Dictionary(
                sessions.map { ($0.id, $0.status) }, uniquingKeysWith: { _, b in b })
            hasBaseline = true
        }

        guard hasBaseline, policy != .never else { return [] }

        var finished: [AgentAnnouncement] = []
        var needsYou: [AgentAnnouncement] = []

        for session in sessions {
            let was = previous[session.id]

            switch session.status {
            case .waiting where was != .waiting:
                // Announced even for a session perch has never seen before. A session that appears
                // already blocked is a session nobody is looking at, which is the case worth
                // catching rather than the one to suppress.
                needsYou.append(AgentAnnouncement(kind: .needsYou, session: session))

            case .idle where was?.isWorking == true:
                finished.append(AgentAnnouncement(kind: .finished, session: session))

            default:
                break
            }
        }

        // A session vanishing is deliberately not an announcement. Quitting the agent is not the
        // same as it finishing, and the person who quit it already knows.

        let allowed: [AgentAnnouncement] =
            switch policy {
            case .all: needsYou + finished
            case .finished: finished
            case .waiting: needsYou
            case .never: []
            }

        return allowed
    }
}
