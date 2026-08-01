import Foundation

/// Persists a single blob of user-typed text to disk.
///
/// Lives beside the config file rather than in it: config is regenerated on save with commented
/// defaults, and threading a free-form scratch buffer through that grammar would corrupt one or
/// both. A sibling file keeps the two independent, and `notes.txt` reads like what it is if a user
/// ever opens the directory.
///
/// Writes are debounced. A notes widget calls `update` on every keystroke; hitting the disk that
/// often would be wasteful and would race with itself. The debounce collapses a burst of edits
/// into one write, and `flush` forces the pending write out at shutdown so nothing is lost.
public actor NotesStore {

    /// Where the notes file lives.
    public static var defaultLocation: URL {
        ConfigPaths.configDirectory.appendingPathComponent("notes.txt")
    }

    private let location: URL
    private let debounce: Duration
    private var pending: Task<Void, Never>?
    private var latest: String

    public init(
        location: URL = NotesStore.defaultLocation,
        debounce: Duration = .milliseconds(400)
    ) {
        self.location = location
        self.debounce = debounce
        self.latest = Self.readSynchronously(at: location)
    }

    /// The last known contents, whether persisted yet or not.
    public var contents: String { latest }

    /// Load the current on-disk value.
    ///
    /// Returns empty string if the file is missing — the widget shows a blank editor and the file
    /// only appears the first time the user types something.
    public func load() -> String { latest }

    /// Record a new value; the write itself is deferred.
    public func update(_ text: String) {
        guard text != latest else { return }
        latest = text

        pending?.cancel()
        pending = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self?.writeIfNeeded()
        }
    }

    /// Write anything outstanding immediately.
    ///
    /// Called on quit so a note typed in the last second before shutdown survives.
    public func flush() {
        pending?.cancel()
        pending = nil
        writeIfNeeded()
    }

    private func writeIfNeeded() {
        try? FileManager.default.createDirectory(
            at: location.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? latest.write(to: location, atomically: true, encoding: .utf8)
    }

    private static func readSynchronously(at location: URL) -> String {
        (try? String(contentsOf: location, encoding: .utf8)) ?? ""
    }
}
