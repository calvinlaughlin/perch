import Foundation
import PerchCore

/// Reassembles JSON lines from a byte stream and decodes them.
///
/// A separate type because the pipe's read handler is `@Sendable` and Swift 6 will not let it
/// mutate captured variables — and because artwork payloads run to hundreds of kilobytes and
/// arrive across several reads, so lines cannot be assumed to align with chunk boundaries.
private final class LineReader: @unchecked Sendable {

    private let lock = NSLock()
    private var buffer = Data()
    private var decoder = MediaStreamDecoder()

    /// Feed bytes in; get whole decoded updates out.
    func consume(_ chunk: Data, emit: (NowPlaying?) -> Void) {
        lock.lock()
        defer { lock.unlock() }

        buffer.append(chunk)

        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)

            switch decoder.decode(line: String(decoding: line, as: UTF8.self)) {
            case .updated(let playing): emit(playing)
            case .cleared: emit(nil)
            case .unchanged: break
            case .malformed(let reason): Log.media.debug("skipped a line: \(reason)")
            }
        }
    }
}

/// Reads now-playing state from the vendored adapter.
///
/// Runs `/usr/bin/perl <script> <framework> stream` and decodes the JSON lines it prints. The
/// subprocess is the whole point: `MediaRemote` is entitlement-gated since macOS 15.4, and Perl's
/// bundle identifier is one of the few that still qualifies.
///
/// Updates are **pushed** by the adapter rather than polled, which is what lets perch show live
/// media while costing nothing between track changes.
public final class MediaRemoteAdapterSource: MediaSource, @unchecked Sendable {

    public let updates: AsyncStream<NowPlaying?>
    private let continuation: AsyncStream<NowPlaying?>.Continuation

    private let location: AdapterLocation

    /// Guards everything below it.
    ///
    /// The class is `@unchecked Sendable` because `Process` is not `Sendable` and has to be
    /// reachable from both the caller and the read handler.
    private let lock = NSLock()
    private var process: Process?
    private var isRunning = false
    private var restartAttempts = 0
    private var restartTask: Task<Void, Never>?

    /// Give up after this many failed restarts.
    ///
    /// Upstream is explicit that a *fatal* adapter error should not be retried — if the loophole
    /// has been closed by a macOS update, relaunching Perl in a loop achieves nothing except
    /// burning CPU on a machine whose owner has not noticed yet.
    private static let maximumRestarts = 5

    public init?(location: AdapterLocation? = AdapterLocation.locate()) {
        guard let location else {
            Log.media.error("adapter not found; media will be unavailable")
            return nil
        }
        self.location = location

        // `AsyncStream` hands its continuation to a closure rather than returning it, so the only
        // way to keep one in a stored property is to let it escape through a local.
        var escapee: AsyncStream<NowPlaying?>.Continuation?
        updates = AsyncStream { escapee = $0 }
        guard let escapee else {
            preconditionFailure("AsyncStream did not provide a continuation")
        }
        continuation = escapee
    }

    deinit {
        restartTask?.cancel()
        process?.terminate()
        continuation.finish()
    }

    // MARK: - MediaSource

    public func start() {
        lock.lock()
        guard !isRunning else {
            lock.unlock()
            return
        }
        isRunning = true
        restartAttempts = 0
        lock.unlock()

        launch()
    }

    public func stop() {
        lock.lock()
        isRunning = false
        let running = process
        process = nil
        restartTask?.cancel()
        restartTask = nil
        lock.unlock()

        // Terminate outside the lock: the termination handler takes it too.
        running?.terminate()
    }

    public func send(_ command: MediaCommand) {
        // A separate short-lived invocation rather than writing to the stream process, which only
        // speaks one direction. These exit immediately.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [
            location.script.path, location.framework.path, "send", String(command.rawValue),
        ]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            Log.media.error("could not send \(command): \(error.localizedDescription)")
        }
    }

    public func seek(to position: TimeInterval) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments =
            [location.script.path, location.framework.path] + Self.seekArguments(position)
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            Log.media.error("could not seek: \(error.localizedDescription)")
        }
    }

    /// The adapter's spelling of a seek.
    ///
    /// Split out and tested because the unit is the trap: the adapter takes **microseconds** as a
    /// positive integer, while every position perch handles elsewhere is seconds as a `Double`.
    /// Passing seconds straight through is a seek to the first moment of the track that looks
    /// almost right for the first few seconds of playback.
    static func seekArguments(_ position: TimeInterval) -> [String] {
        guard position.isFinite, position > 0 else { return ["seek", "0"] }

        let microseconds = (position * 1_000_000).rounded()

        // Compared, not `min`-ed. `Double(Int.max)` is not `Int.max`: it rounds *up* to 2^63,
        // which is one past the largest `Int`, so clamping to it and converting traps on exactly
        // the input the clamp was written to survive. Anything below 2^63 converts safely.
        guard microseconds < Double(Int.max) else { return ["seek", String(Int.max)] }
        return ["seek", String(Int(microseconds))]
    }

    // MARK: - The subprocess

    /// Kill any adapter left behind by a previous perch.
    ///
    /// `Process.terminate` handles the ordinary case, and `stop()` is called on quit — but a perch
    /// that is force-quit or crashes never gets to run either, and the helper it started is
    /// reparented to launchd and runs forever. Nothing else reaps it, so orphans accumulate one
    /// per crash until the machine is restarted. Since perch is the only thing that launches this
    /// script, anything already running it is by definition stale.
    ///
    /// This does assume a single perch. Two running at once would fight over the helper, but they
    /// would already be fighting over the notch.
    private func reapOrphans() {
        let search = Process()
        search.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        search.arguments = ["-f", location.script.path]
        search.standardOutput = FileHandle.nullDevice
        search.standardError = FileHandle.nullDevice

        try? search.run()
        search.waitUntilExit()

        // pkill exits 1 when it matched nothing, which is the normal case.
        if search.terminationStatus == 0 {
            Log.media.info("cleaned up an adapter left by a previous run")
        }
    }

    /// Ask for the current state once, rather than waiting for it to change.
    ///
    /// `stream` emits an empty payload immediately and then says nothing until playback changes —
    /// which, if a track is already playing and nobody touches it, can be minutes. Without this
    /// the notch shows "nothing playing" over a track that is audibly playing.
    private func seedInitialState() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [location.script.path, location.framework.path, "get"]
        let output = Pipe()
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice

        do { try task.run() } catch { return }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard !data.isEmpty else { return }

        // `get` returns a bare payload; the stream decoder expects it wrapped like a stream line.
        var decoder = MediaStreamDecoder()
        let wrapped =
            #"{"type":"data","diff":false,"payload":"# + String(decoding: data, as: UTF8.self) + "}"
        if case .updated(let playing) = decoder.decode(line: wrapped) {
            continuation.yield(playing)
        }
    }

    private func launch() {
        reapOrphans()

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [location.script.path, location.framework.path, "stream"]

        let output = Pipe()
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice

        // Decoding state is per-launch: the adapter sends diffs, so lines only make sense in
        // sequence, and a restart must begin from a clean slate rather than a stale track.
        let reader = LineReader()

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            reader.consume(chunk) { self?.continuation.yield($0) }
        }

        task.terminationHandler = { [weak self] finished in
            output.fileHandleForReading.readabilityHandler = nil
            self?.processDidExit(status: finished.terminationStatus)
        }

        do {
            try task.run()
            lock.lock()
            process = task
            lock.unlock()
            Log.media.info("adapter started")

            // Off the caller's thread: this spawns a second short-lived process and waits on it.
            Task.detached { [weak self] in self?.seedInitialState() }
        } catch {
            Log.media.error("could not start adapter: \(error.localizedDescription)")
            processDidExit(status: -1)
        }
    }

    /// Decide whether to bring the adapter back.
    private func processDidExit(status: Int32) {
        lock.lock()
        guard isRunning else {
            lock.unlock()
            return  // We asked it to stop.
        }

        restartAttempts += 1
        let attempt = restartAttempts
        guard attempt <= Self.maximumRestarts else {
            isRunning = false
            lock.unlock()
            Log.media.error(
                """
                adapter exited \(attempt) times (status \(status)); giving up. If this began after \
                a macOS update, run the adapter's `test` command — the entitlement it relies on \
                may have been withdrawn.
                """
            )
            continuation.yield(nil)
            return
        }
        lock.unlock()

        // Back off so a persistently failing adapter does not spin.
        let delay = Duration.milliseconds(250 * (1 << (attempt - 1)))
        Log.media.info("adapter exited (status \(status)); retrying in \(delay)")

        let task = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.launch()
        }
        lock.lock()
        restartTask = task
        lock.unlock()
    }
}
