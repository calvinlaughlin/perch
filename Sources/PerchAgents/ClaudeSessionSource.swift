import Foundation

/// Watches Claude Code's session directory and reports the live sessions.
///
/// Watching the directory is not enough, and this is the whole difficulty of the file.
///
/// A `vnode` watch on a directory fires when its *contents list* changes — a file created, deleted,
/// or renamed. Claude Code creates `<pid>.json` when a session starts and removes it when the
/// session ends, so the directory watch catches sessions appearing and disappearing. But a status
/// change is written straight over the existing file, same inode, same name: the directory never
/// notices, and a source built on the directory alone reports every session as whatever it was when
/// it started and never changes again. It looks like it works, because sessions do appear.
///
/// So each session file is watched individually as well, and those watches are re-armed on every
/// scan. That is the exact inverse of `ConfigWatcher`, where the file is replaced by an atomic save
/// and the directory watch is what rescues it — worth knowing that the two cases exist and need
/// opposite things.
///
/// Both are `kqueue` watches: the kernel wakes us when something happens and costs nothing when
/// nothing does. Nothing here polls.
@MainActor
public final class ClaudeSessionSource: AgentSessionSource {

    private let directory: URL
    private let debounce: Duration
    private let isRunning: @Sendable (Int32) -> Bool

    public let updates: AsyncStream<[AgentSession]>
    private let continuation: AsyncStream<[AgentSession]>.Continuation

    private var directorySource: (any DispatchSourceFileSystemObject)?

    /// One watch per session file, keyed by file name.
    private var fileSources: [String: any DispatchSourceFileSystemObject] = [:]

    private var pendingScan: Task<Void, Never>?
    private var isWatching = false

    /// The last thing sent, so an event that changed nothing sends nothing.
    private var latest: [AgentSession] = []

    private let queue = DispatchQueue(label: "dev.perch.claude-sessions")

    /// Create a source.
    ///
    /// - Parameters:
    ///   - directory: where the session files are. Injectable so tests can drive a real directory
    ///     of their own rather than whatever the machine running them happens to have open.
    ///   - debounce: how long to let the directory settle. A session starting writes the file more
    ///     than once in quick succession, and scanning each write means reading a file that is
    ///     half-written — which decodes to a session with no status.
    ///   - isRunning: how to tell whether a pid is alive, injectable for the same reason.
    public init(
        directory: URL = ClaudeSessionFile.directory,
        debounce: Duration = .milliseconds(60),
        isRunning: @escaping @Sendable (Int32) -> Bool = ClaudeSessionFile.isRunning
    ) {
        self.directory = directory
        self.debounce = debounce
        self.isRunning = isRunning

        (updates, continuation) = AsyncStream.makeStream(
            // Only the newest snapshot matters. A burst of writes must not queue up a backlog of
            // stale session lists for a consumer to walk through one at a time.
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    deinit {
        continuation.finish()
    }

    public func start() {
        guard !isWatching else { return }
        isWatching = true

        watchDirectory()
        scan()
    }

    public func stop() {
        isWatching = false

        pendingScan?.cancel()
        pendingScan = nil

        directorySource?.cancel()
        directorySource = nil

        for source in fileSources.values { source.cancel() }
        fileSources.removeAll()

        // Deliberately keeps `latest`. Nothing is re-sent on the next `start()` unless it actually
        // differs, so waking the display does not repaint a strip that is showing the right thing.
    }

    // MARK: - Watching

    private func watchDirectory() {
        directorySource?.cancel()
        directorySource = nil

        // Not created if missing, unlike the config directory. An absent directory means Claude
        // Code has never run here, and making it would be perch inventing state in somebody else's
        // application-support folder. The widget simply shows nothing.
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )
        // `@Sendable` is load-bearing and its absence is not a compile error — see the same note in
        // `ConfigWatcher`. Without it this closure inherits `@MainActor` from the enclosing type,
        // and dispatch runs it on `queue` anyway, which trips the isolation assertion and takes the
        // process down with a `SIGTRAP` the first time a session starts.
        source.setEventHandler { @Sendable [weak self] in
            Task { @MainActor in self?.scheduleScan() }
        }
        source.setCancelHandler { @Sendable in close(descriptor) }
        source.resume()
        directorySource = source
    }

    /// Watch one session file for writes.
    private func watchFile(named name: String) {
        guard fileSources[name] == nil else { return }

        let descriptor = open(directory.appendingPathComponent(name).path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete, .attrib],
            queue: queue
        )
        source.setEventHandler { @Sendable [weak self] in
            Task { @MainActor in self?.scheduleScan() }
        }
        source.setCancelHandler { @Sendable in close(descriptor) }
        source.resume()
        fileSources[name] = source
    }

    private func scheduleScan() {
        pendingScan?.cancel()
        pendingScan = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.debounce)
            guard !Task.isCancelled else { return }
            self.scan()
        }
    }

    // MARK: - Reading

    /// Read every session file, re-arm the per-file watches, and send if anything changed.
    private func scan() {
        let names =
            (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []

        var sessions: [AgentSession] = []
        var live: Set<String> = []

        for name in names {
            guard let pid = ClaudeSessionFile.pid(forFileNamed: name) else { continue }

            // A file whose process is gone is a session that crashed or was killed without
            // cleaning up. Watching it would be watching a file nothing will ever write again.
            guard isRunning(pid) else { continue }

            live.insert(name)

            guard
                let data = try? Data(contentsOf: directory.appendingPathComponent(name)),
                let session = ClaudeSessionFile.decode(data, pid: pid)
            else { continue }

            sessions.append(session)
        }

        // Arm watches for files that appeared, drop the ones for files that went away. Both halves
        // matter: without the first, a session that starts is never seen to change; without the
        // second, the descriptors accumulate for the lifetime of the app.
        for name in live { watchFile(named: name) }
        for (name, source) in fileSources where !live.contains(name) {
            source.cancel()
            fileSources.removeValue(forKey: name)
        }

        // Oldest first, so a session keeps its place in the strip instead of jumping about as
        // statuses change and the directory listing comes back in a different order.
        sessions.sort {
            ($0.startedAt ?? .distantPast, $0.id) < ($1.startedAt ?? .distantPast, $1.id)
        }

        guard sessions != latest else { return }
        latest = sessions
        continuation.yield(sessions)
    }
}
