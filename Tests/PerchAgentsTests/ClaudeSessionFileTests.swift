import Foundation
import Testing

@testable import PerchAgents

@Suite("Reading Claude session files")
struct ClaudeSessionFileTests {

    /// A real file, as Claude Code 2.1.220 writes it.
    private let live = Data(
        """
        {"pid":70439,"sessionId":"cab08384-2459-4c89-85f1-9e99545a01f4",\
        "cwd":"/Users/someone/personal/perch","startedAt":1785385517232,\
        "procStart":"Thu Jul 30 04:25:16 2026","version":"2.1.220","peerProtocol":1,\
        "kind":"interactive","entrypoint":"cli","name":"perch-af","nameSource":"derived",\
        "status":"busy","updatedAt":1785385537169,"statusUpdatedAt":1785385537169}
        """.utf8)

    @Test("A session file decodes")
    func decodesLiveFile() throws {
        let session = try #require(ClaudeSessionFile.decode(live, pid: 70439))

        #expect(session.id == 70439)
        #expect(session.name == "perch-af")
        #expect(session.directory == "/Users/someone/personal/perch")
        #expect(session.status == .busy)
        #expect(session.label == "perch-af")
    }

    @Test("The pid comes from the file name, not the contents")
    func trustsTheFileName() throws {
        // The name is what liveness is checked against. If the two ever disagreed, trusting the
        // contents would mean checking one process and drawing another.
        let session = try #require(ClaudeSessionFile.decode(live, pid: 999))
        #expect(session.id == 999)
    }

    @Test("Every status Claude Code publishes is understood")
    func decodesEveryStatus() throws {
        for status in ["busy", "shell", "waiting", "idle"] {
            let data = Data(#"{"status":"\#(status)"}"#.utf8)
            let session = try #require(ClaudeSessionFile.decode(data, pid: 1))
            #expect(session.status.rawValue == status)
        }
    }

    @Test("A status from the future is inert rather than mistaken for one we know")
    func unknownStatusIsUnknown() throws {
        let session = try #require(
            ClaudeSessionFile.decode(Data(#"{"status":"compacting"}"#.utf8), pid: 1))

        #expect(session.status == .unknown)
        #expect(!session.status.isWorking)
    }

    @Test("A half-written file decodes to a session with no status")
    func toleratesMissingFields() throws {
        // The file is created first and filled in afterwards, so a read can land in between.
        let session = try #require(ClaudeSessionFile.decode(Data("{}".utf8), pid: 42))
        #expect(session.status == .unknown)
        #expect(session.label == "session 42")
    }

    @Test("Garbage is skipped, not thrown")
    func rejectsNonsense() {
        #expect(ClaudeSessionFile.decode(Data("not json".utf8), pid: 1) == nil)
    }

    @Test("Daemons are not shown; background sessions are")
    func filtersByKind() {
        #expect(ClaudeSessionFile.decode(Data(#"{"kind":"daemon"}"#.utf8), pid: 1) == nil)
        #expect(ClaudeSessionFile.decode(Data(#"{"kind":"daemon-worker"}"#.utf8), pid: 1) == nil)
        #expect(ClaudeSessionFile.decode(Data(#"{"kind":"bg"}"#.utf8), pid: 1) != nil)
        #expect(ClaudeSessionFile.decode(Data(#"{"kind":"interactive"}"#.utf8), pid: 1) != nil)
    }

    @Test("Only <digits>.json is a session file")
    func parsesFileNames() {
        #expect(ClaudeSessionFile.pid(forFileNamed: "70439.json") == 70439)
        #expect(ClaudeSessionFile.pid(forFileNamed: "notes.json") == nil)
        #expect(ClaudeSessionFile.pid(forFileNamed: "70439.txt") == nil)
        #expect(ClaudeSessionFile.pid(forFileNamed: ".json") == nil)
        #expect(ClaudeSessionFile.pid(forFileNamed: "70439") == nil)
    }

    @Test("A session with no name falls back to its directory, then its pid")
    func labelFallsBack() {
        #expect(
            AgentSession(id: 1, directory: "/Users/someone/code/musica", status: .idle).label
                == "musica")
        #expect(AgentSession(id: 1, status: .idle).label == "session 1")
        #expect(AgentSession(id: 1, name: "", directory: "", status: .idle).label == "session 1")
    }

    @Test("This process is running and pid 0 is not")
    func detectsLiveness() {
        #expect(ClaudeSessionFile.isRunning(ProcessInfo.processInfo.processIdentifier))
        #expect(!ClaudeSessionFile.isRunning(0))
        #expect(!ClaudeSessionFile.isRunning(-1))
    }
}
