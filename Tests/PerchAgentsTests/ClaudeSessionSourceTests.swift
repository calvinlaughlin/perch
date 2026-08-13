import Foundation
import Testing

@testable import PerchAgents

/// A scratch session directory, cleaned up on deinit.
@MainActor
private final class Scratch {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("perch-sessions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Write a session file the way Claude Code does — straight over the top, same inode.
    ///
    /// Not `atomically:`, which would write a temporary file and rename it. That distinction is the
    /// entire point of these tests: an atomic save bumps the directory, an in-place write does not,
    /// and only one of them is what actually happens.
    func write(pid: Int32, status: String, name: String = "s", kind: String = "interactive") throws
    {
        let json = """
            {"pid":\(pid),"name":"\(name)","cwd":"/tmp/work","kind":"\(kind)",\
            "status":"\(status)","startedAt":\(1_785_385_517_232 + Int(pid))}
            """
        let file = directory.appendingPathComponent("\(pid).json")

        guard FileManager.default.fileExists(atPath: file.path) else {
            try Data(json.utf8).write(to: file)
            return
        }

        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(json.utf8))
        try handle.close()
    }

    func remove(pid: Int32) throws {
        try FileManager.default.removeItem(
            at: directory.appendingPathComponent("\(pid).json"))
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}

/// Collects snapshots and lets a test wait for the next one.
@MainActor
private final class Snapshots {
    private var task: Task<Void, Never>?
    private var received: [[AgentSession]] = []
    private var waiter: CheckedContinuation<[AgentSession]?, Never>?

    init(_ source: any AgentSessionSource) {
        task = Task { [weak self] in
            for await sessions in source.updates {
                await MainActor.run { self?.record(sessions) }
            }
        }
    }

    deinit { task?.cancel() }

    private func record(_ sessions: [AgentSession]) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: sessions)
        } else {
            received.append(sessions)
        }
    }

    /// Wait for a snapshot, or give up.
    ///
    /// Times out rather than hanging CI when an update never arrives — which, for the watch these
    /// tests exist to check, is exactly how the failure presents.
    func next(timeout: Duration = .seconds(5)) async -> [AgentSession]? {
        if !received.isEmpty { return received.removeFirst() }

        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let waiter = self?.waiter else { return }
                self?.waiter = nil
                waiter.resume(returning: nil)
            }
        }
        defer { timeoutTask.cancel() }

        return await withCheckedContinuation { continuation in
            self.waiter = continuation
        }
    }
}

@Suite("Watching the session directory")
@MainActor
struct ClaudeSessionSourceTests {

    /// Every pid in these tests is alive, unless a test says otherwise.
    private func source(
        _ scratch: Scratch, isRunning: @escaping @Sendable (Int32) -> Bool = { _ in true }
    ) -> ClaudeSessionSource {
        ClaudeSessionSource(
            directory: scratch.directory, debounce: .milliseconds(20), isRunning: isRunning)
    }

    @Test("Starting reports the sessions already there")
    func readsExistingSessions() async throws {
        let scratch = try Scratch()
        try scratch.write(pid: 101, status: "busy", name: "alpha")

        let source = source(scratch)
        let snapshots = Snapshots(source)
        defer { source.stop() }
        source.start()

        let sessions = try #require(await snapshots.next())
        #expect(sessions.map(\.name) == ["alpha"])
        #expect(sessions.first?.status == .busy)
    }

    @Test("A session starting is noticed")
    func noticesNewSession() async throws {
        let scratch = try Scratch()
        let source = source(scratch)
        let snapshots = Snapshots(source)
        defer { source.stop() }
        source.start()

        // No baseline is waited for: starting on an empty directory sends nothing, because nothing
        // has changed. Only meaningful changes are sent, and "still empty" is not one.
        try scratch.write(pid: 202, status: "busy")

        let sessions = try #require(await snapshots.next())
        #expect(sessions.map(\.id) == [202])
    }

    @Test("A status change written in place is noticed")
    func noticesInPlaceStatusChange() async throws {
        // The test this file exists for.
        //
        // Claude Code rewrites `<pid>.json` straight over the top: same name, same inode. A watch
        // on the directory alone never fires for that, so a source without per-file watches reports
        // every session as whatever it was when it started and never changes again — while still
        // passing every other test here, because sessions do appear and disappear.
        let scratch = try Scratch()
        try scratch.write(pid: 303, status: "busy")

        let source = source(scratch)
        let snapshots = Snapshots(source)
        defer { source.stop() }
        source.start()

        let first = try #require(await snapshots.next())
        #expect(first.first?.status == .busy)

        try scratch.write(pid: 303, status: "idle")

        let second = try #require(await snapshots.next())
        #expect(second.first?.status == .idle)
    }

    @Test("A session that starts later also has its status changes noticed")
    func armsWatchesForSessionsThatArriveLater() async throws {
        // The per-file watch has to be armed on every scan, not only at startup. Arming it once
        // means the sessions running when perch launched update and nothing started afterwards
        // ever does.
        let scratch = try Scratch()
        let source = source(scratch)
        let snapshots = Snapshots(source)
        defer { source.stop() }
        source.start()

        try scratch.write(pid: 404, status: "busy")
        var sessions = try #require(await snapshots.next())
        while sessions.isEmpty { sessions = try #require(await snapshots.next()) }
        #expect(sessions.first?.status == .busy)

        try scratch.write(pid: 404, status: "waiting")

        let updated = try #require(await snapshots.next())
        #expect(updated.first?.status == .waiting)
    }

    @Test("A session ending is noticed")
    func noticesRemovedSession() async throws {
        let scratch = try Scratch()
        try scratch.write(pid: 505, status: "busy")

        let source = source(scratch)
        let snapshots = Snapshots(source)
        defer { source.stop() }
        source.start()
        _ = try #require(await snapshots.next())

        try scratch.remove(pid: 505)

        let sessions = try #require(await snapshots.next())
        #expect(sessions.isEmpty)
    }

    @Test("A session file left behind by a dead process is ignored")
    func ignoresStaleFiles() async throws {
        // A crash or a kill leaves the file behind. Showing it would mean a dot that never goes
        // away, for a session that is not there.
        let scratch = try Scratch()
        try scratch.write(pid: 606, status: "busy", name: "ghost")
        try scratch.write(pid: 607, status: "busy", name: "alive")

        let source = source(scratch, isRunning: { $0 != 606 })
        let snapshots = Snapshots(source)
        defer { source.stop() }
        source.start()

        let sessions = try #require(await snapshots.next())
        #expect(sessions.map(\.name) == ["alive"])
    }

    @Test("Files that are not sessions are ignored")
    func ignoresOtherFiles() async throws {
        let scratch = try Scratch()
        try Data("{}".utf8).write(to: scratch.directory.appendingPathComponent("notes.json"))
        try scratch.write(pid: 707, status: "idle")

        let source = source(scratch)
        let snapshots = Snapshots(source)
        defer { source.stop() }
        source.start()

        let sessions = try #require(await snapshots.next())
        #expect(sessions.map(\.id) == [707])
    }

    @Test("Sessions keep a stable order as their statuses change")
    func ordersByStartTime() async throws {
        let scratch = try Scratch()
        try scratch.write(pid: 803, status: "busy")
        try scratch.write(pid: 801, status: "busy")
        try scratch.write(pid: 802, status: "busy")

        let source = source(scratch)
        let snapshots = Snapshots(source)
        defer { source.stop() }
        source.start()

        let sessions = try #require(await snapshots.next())
        #expect(sessions.map(\.id) == [801, 802, 803])
    }

    @Test("A missing directory is not an error")
    func toleratesMissingDirectory() async throws {
        // Claude Code has never run on this machine. The widget shows nothing; perch carries on.
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("perch-absent-\(UUID().uuidString)", isDirectory: true)

        let source = ClaudeSessionSource(directory: missing, isRunning: { _ in true })
        defer { source.stop() }
        source.start()

        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    @Test("Stopping releases every watch")
    func stopReleasesWatches() async throws {
        let scratch = try Scratch()
        try scratch.write(pid: 901, status: "busy")

        let source = source(scratch)
        let snapshots = Snapshots(source)
        source.start()
        _ = try #require(await snapshots.next())

        source.stop()
        try scratch.write(pid: 901, status: "idle")

        // Nothing should arrive. A shorter wait than the timeout used elsewhere, because this test
        // is meant to spend it.
        #expect(await snapshots.next(timeout: .milliseconds(400)) == nil)
    }
}
