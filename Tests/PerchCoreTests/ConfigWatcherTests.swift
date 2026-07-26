import Foundation
import Testing

@testable import PerchCore

/// A scratch directory with a config file in it, cleaned up on deinit.
@MainActor
private final class Scratch {
    let directory: URL
    let file: URL

    init(_ contents: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("perch-watch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appendingPathComponent("config")
        try contents.write(to: file, atomically: false, encoding: .utf8)
    }

    /// Append, the way `echo >>` does.
    func append(_ line: String) throws {
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n\(line)\n".utf8))
        try handle.close()
    }

    /// Replace via a temporary file and a rename, the way vim and VS Code save.
    func atomicallyReplace(with contents: String) throws {
        let temporary = directory.appendingPathComponent("config.tmp")
        try contents.write(to: temporary, atomically: false, encoding: .utf8)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}

/// Collects reloads and lets a test wait for the next one.
@MainActor
private final class Reloads {
    private var received: [ConfigLoadResult] = []
    private var waiter: CheckedContinuation<ConfigLoadResult, Never>?

    func record(_ result: ConfigLoadResult) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: result)
        } else {
            received.append(result)
        }
    }

    /// Wait for a reload, or give up.
    ///
    /// Times out rather than hanging a CI job when a reload never arrives.
    func next(timeout: Duration = .seconds(5)) async -> ConfigLoadResult? {
        if !received.isEmpty { return received.removeFirst() }

        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let waiter = self?.waiter else { return }
                self?.waiter = nil
                waiter.resume(returning: ConfigLoadResult(config: Config(), diagnostics: []))
            }
        }
        defer { timeoutTask.cancel() }

        return await withCheckedContinuation { continuation in
            self.waiter = continuation
        }
    }
}

@Suite("Config live reload")
@MainActor
struct ConfigWatcherTests {

    @Test("Starting the watcher loads the file immediately")
    func loadsOnStart() async throws {
        let scratch = try Scratch("expanded-height = 111")
        let reloads = Reloads()

        let watcher = ConfigWatcher(url: scratch.file) { reloads.record($0) }
        defer { watcher.stop() }
        watcher.start()

        let result = await reloads.next()
        #expect(result?.config.expandedHeight == 111)
    }

    @Test("Appending to the file triggers a reload")
    func reloadsOnAppend() async throws {
        let scratch = try Scratch("expanded-height = 111")
        let reloads = Reloads()

        let watcher = ConfigWatcher(url: scratch.file) { reloads.record($0) }
        defer { watcher.stop() }
        watcher.start()
        _ = await reloads.next()  // the initial load

        try scratch.append("expanded-width = 222")

        let result = await reloads.next()
        #expect(result?.config.expandedWidth == 222)
    }

    @Test("An atomic save triggers a reload")
    func reloadsOnAtomicReplace() async throws {
        // This is the case that matters: editors do not write in place. They write a temporary
        // file and rename it over the original, which leaves a watch on the old inode reporting
        // on a file nobody will read again.
        let scratch = try Scratch("expanded-height = 111")
        let reloads = Reloads()

        let watcher = ConfigWatcher(url: scratch.file) { reloads.record($0) }
        defer { watcher.stop() }
        watcher.start()
        _ = await reloads.next()

        try scratch.atomicallyReplace(with: "expanded-height = 333")

        let result = await reloads.next()
        #expect(result?.config.expandedHeight == 333)
    }

    @Test("Reload survives repeated atomic saves")
    func survivesRepeatedAtomicSaves() async throws {
        // One rename is easy to handle by accident. The bug shows up on the second save, once the
        // watch has been re-armed onto a file that was itself replaced.
        let scratch = try Scratch("expanded-height = 100")
        let reloads = Reloads()

        let watcher = ConfigWatcher(url: scratch.file) { reloads.record($0) }
        defer { watcher.stop() }
        watcher.start()
        _ = await reloads.next()

        for height in [200, 300, 400] {
            try scratch.atomicallyReplace(with: "expanded-height = \(height)")
            let result = await reloads.next()
            #expect(result?.config.expandedHeight == CGFloat(height))
        }
    }

    @Test("A broken file reports diagnostics without crashing")
    func reportsDiagnosticsOnBrokenFile() async throws {
        let scratch = try Scratch("expanded-height = 111")
        let reloads = Reloads()

        let watcher = ConfigWatcher(url: scratch.file) { reloads.record($0) }
        defer { watcher.stop() }
        watcher.start()
        _ = await reloads.next()

        try scratch.atomicallyReplace(with: "open-on = sideways")

        let result = await reloads.next()
        #expect(result?.diagnostics.isEmpty == false)
    }
}
