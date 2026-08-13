import Foundation
import Testing

@testable import PerchAgents

private func session(
    _ id: Int32, _ status: AgentStatus, waitingFor: String? = nil
) -> AgentSession {
    AgentSession(id: id, name: "s\(id)", status: status, waitingFor: waitingFor)
}

@Suite("Deciding what is worth announcing")
struct AgentSessionMonitorTests {

    @Test("The first observation is a baseline and says nothing")
    func firstObservationIsSilent() {
        // Otherwise launching perch while three sessions sat finished would announce all three,
        // none of which is news.
        var monitor = AgentSessionMonitor()
        #expect(monitor.observe([session(1, .idle), session(2, .waiting)]).isEmpty)
    }

    @Test("A session finishing is announced")
    func announcesFinish() {
        var monitor = AgentSessionMonitor()
        _ = monitor.observe([session(1, .busy)])

        let announcements = monitor.observe([session(1, .idle)])
        #expect(announcements.count == 1)
        #expect(announcements.first?.kind == .finished)
        #expect(announcements.first?.session.id == 1)
    }

    @Test("A session finishing a shell command is announced too")
    func announcesFinishFromShell() {
        var monitor = AgentSessionMonitor()
        _ = monitor.observe([session(1, .shell)])
        #expect(monitor.observe([session(1, .idle)]).first?.kind == .finished)
    }

    @Test("A session blocking on you is announced")
    func announcesWaiting() {
        var monitor = AgentSessionMonitor()
        _ = monitor.observe([session(1, .busy)])

        let announcements = monitor.observe([session(1, .waiting, waitingFor: "input needed")])
        #expect(announcements.first?.kind == .needsYou)
        #expect(announcements.first?.session.waitingFor == "input needed")
    }

    @Test("Staying in the same state announces nothing")
    func staysQuiet() {
        var monitor = AgentSessionMonitor()
        _ = monitor.observe([session(1, .busy)])
        _ = monitor.observe([session(1, .waiting)])

        #expect(monitor.observe([session(1, .waiting)]).isEmpty)
        #expect(monitor.observe([session(1, .waiting)]).isEmpty)
    }

    @Test("Starting work again announces nothing")
    func idleToBusyIsSilent() {
        var monitor = AgentSessionMonitor()
        _ = monitor.observe([session(1, .idle)])
        #expect(monitor.observe([session(1, .busy)]).isEmpty)
    }

    @Test("A session that appears already blocked is announced")
    func announcesNewWaitingSession() {
        // Nobody is looking at it, which is the case worth catching rather than the one to suppress.
        var monitor = AgentSessionMonitor()
        _ = monitor.observe([])
        #expect(monitor.observe([session(9, .waiting)]).first?.kind == .needsYou)
    }

    @Test("A session that appears at the prompt is not announced")
    func newIdleSessionIsSilent() {
        // Opening a terminal and starting Claude is not an achievement to interrupt anybody about.
        var monitor = AgentSessionMonitor()
        _ = monitor.observe([])
        #expect(monitor.observe([session(9, .idle)]).isEmpty)
    }

    @Test("Quitting a session is not the same as it finishing")
    func removalIsSilent() {
        var monitor = AgentSessionMonitor()
        _ = monitor.observe([session(1, .busy)])
        #expect(monitor.observe([]).isEmpty)
    }

    @Test("A blocked session is announced once, not again when it finishes the same way")
    func waitingThenIdleAnnouncesBoth() {
        var monitor = AgentSessionMonitor()
        _ = monitor.observe([session(1, .busy)])
        #expect(monitor.observe([session(1, .waiting)]).count == 1)

        // Answering the prompt puts it back to work, and finishing then announces normally.
        #expect(monitor.observe([session(1, .busy)]).isEmpty)
        #expect(monitor.observe([session(1, .idle)]).first?.kind == .finished)
    }

    @Test("A blocked session is announced before a finished one")
    func waitingOutranksFinished() {
        // Only one can be shown in the two seconds a peek lasts, and the one still blocked is the
        // one that is not going anywhere until somebody looks.
        var monitor = AgentSessionMonitor()
        _ = monitor.observe([session(1, .busy), session(2, .busy)])

        let announcements = monitor.observe([session(1, .idle), session(2, .waiting)])
        #expect(announcements.map(\.kind) == [.needsYou, .finished])
    }

    @Test("An unrecognised status neither announces nor counts as having worked")
    func unknownIsInert() {
        var monitor = AgentSessionMonitor()
        _ = monitor.observe([session(1, .busy)])

        #expect(monitor.observe([session(1, .unknown)]).isEmpty)
        // Having passed through a status we do not understand, going idle is not a finish we can
        // vouch for.
        #expect(monitor.observe([session(1, .idle)]).isEmpty)
    }

    @Test(
        "The policy decides what gets through",
        arguments: [
            (AgentAnnouncePolicy.all, 2),
            (.finished, 1),
            (.waiting, 1),
            (.never, 0),
        ])
    func honoursPolicy(policy: AgentAnnouncePolicy, expected: Int) {
        var monitor = AgentSessionMonitor(policy: policy)
        _ = monitor.observe([session(1, .busy), session(2, .busy)])
        #expect(monitor.observe([session(1, .idle), session(2, .waiting)]).count == expected)
    }
}
