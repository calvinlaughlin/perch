import Foundation

/// Somewhere the list of running agent sessions comes from.
///
/// perch reads Claude Code's session files today. That is a private directory rather than a
/// published interface, and its shape can change under us — so this protocol is the seam. When it
/// does change, or when a second agent is worth showing, only the conforming type moves.
@MainActor
public protocol AgentSessionSource: AnyObject {

    /// The running sessions, re-sent whenever they change.
    ///
    /// Only meaningful changes are sent: a write that leaves every session looking the same
    /// produces nothing.
    var updates: AsyncStream<[AgentSession]> { get }

    /// Begin watching. Calling twice is a no-op.
    func start()

    /// Stop and release every watch. Calling twice is a no-op.
    func stop()
}
