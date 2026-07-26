import Foundation

/// Watches the config file and reloads it when it changes.
///
/// Watching the *directory* as well as the file is the part that matters. Editors do not write
/// files in place — vim, VS Code, and anything using an atomic save write a temporary file and
/// rename it over the original. The original inode survives, so a watch on the file alone keeps
/// reporting on a file nobody will ever read again, and reload silently stops working after the
/// first save. The directory watch catches the replacement and re-arms the file watch.
@MainActor
public final class ConfigWatcher {

    private let url: URL
    private let debounce: Duration
    private let onChange: @MainActor (ConfigLoadResult) -> Void

    private var fileSource: (any DispatchSourceFileSystemObject)?
    private var directorySource: (any DispatchSourceFileSystemObject)?
    private var pendingReload: Task<Void, Never>?

    private let queue = DispatchQueue(label: "dev.perch.config-watcher")

    /// Create a watcher.
    ///
    /// `debounce` is how long to wait for the file to settle: a save is several filesystem events
    /// in quick succession, and reloading on each one means parsing a half-written file.
    public init(
        url: URL = ConfigPaths.configFile,
        debounce: Duration = .milliseconds(50),
        onChange: @escaping @MainActor (ConfigLoadResult) -> Void
    ) {
        self.url = url
        self.debounce = debounce
        self.onChange = onChange
    }

    deinit {
        fileSource?.cancel()
        directorySource?.cancel()
    }

    /// Load the config once, then watch for changes.
    public func start() {
        onChange(ConfigLoader.load(contentsOf: url))
        watchDirectory()
        watchFile()
    }

    /// Stop watching.
    ///
    /// Safe to call more than once.
    public func stop() {
        pendingReload?.cancel()
        pendingReload = nil
        fileSource?.cancel()
        fileSource = nil
        directorySource?.cancel()
        directorySource = nil
    }

    /// Reload immediately, ignoring the debounce.
    public func reloadNow() {
        pendingReload?.cancel()
        pendingReload = nil
        onChange(ConfigLoader.load(contentsOf: url))
    }

    // MARK: - Watching

    private func watchFile() {
        fileSource?.cancel()
        fileSource = nil

        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }  // No file yet; the directory watch will notice one.

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete, .attrib],
            queue: queue
        )
        // The `@Sendable` is load-bearing and its absence is not a compile error.
        //
        // This closure is formed inside a `@MainActor` type, so without the annotation Swift
        // infers it as `@MainActor`-isolated. `DispatchSource` knows nothing about actors and runs
        // it on `queue`, whereupon the isolation check fails and the process dies with SIGTRAP
        // inside `_dispatch_assert_queue_fail` — at the first config change, with a clean build and
        // no warning. Marking it `@Sendable` opts the closure out of inheriting that isolation, so
        // it is genuinely non-isolated and hops to the main actor explicitly below.
        source.setEventHandler { @Sendable [weak self] in
            Task { @MainActor in self?.scheduleReload(rearmFileWatch: true) }
        }
        source.setCancelHandler { @Sendable in close(descriptor) }
        source.resume()
        fileSource = source
    }

    private func watchDirectory() {
        directorySource?.cancel()
        directorySource = nil

        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )

        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { @Sendable [weak self] in
            Task { @MainActor in self?.scheduleReload(rearmFileWatch: true) }
        }
        source.setCancelHandler { @Sendable in close(descriptor) }
        source.resume()
        directorySource = source
    }

    private func scheduleReload(rearmFileWatch: Bool) {
        pendingReload?.cancel()
        pendingReload = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.debounce)
            guard !Task.isCancelled else { return }

            if rearmFileWatch { self.watchFile() }
            self.onChange(ConfigLoader.load(contentsOf: self.url))
        }
    }
}
