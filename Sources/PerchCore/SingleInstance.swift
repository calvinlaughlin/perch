import Foundation

/// Holds an exclusive lock for as long as perch runs, so only one copy can.
///
/// Two perches are not merely untidy — they draw two panels over the same notch, both respond to
/// the same hover, and both reap each other's media helper, since orphan cleanup assumes anything
/// running the adapter script is stale.
///
/// Uses `flock` on a file rather than checking for a running process by bundle identifier: perch
/// is regularly run straight from a build directory during development, where there is no bundle
/// identity to check, and a lock the kernel releases on exit cannot be left stale by a crash.
public final class SingleInstanceLock {

    private let descriptor: Int32

    /// The path locked by default.
    public static var defaultPath: URL {
        ConfigPaths.configDirectory.appendingPathComponent("perch.lock")
    }

    /// Take the lock, or fail because another perch holds it.
    ///
    /// - Returns: nil if another instance is already running.
    public init?(path: URL = SingleInstanceLock.defaultPath) {
        try? FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        descriptor = open(path.path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else { return nil }

        // Non-blocking: a second perch should say so and exit, not wait for the first to quit.
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }

        // Record the owner, so `perch` can say which process is in the way.
        let pid = "\(ProcessInfo.processInfo.processIdentifier)\n"
        ftruncate(descriptor, 0)
        _ = pid.withCString { write(descriptor, $0, strlen($0)) }
    }

    deinit {
        // The kernel releases the lock when the descriptor closes, including on crash, so there
        // is no stale-lock case to recover from.
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }

    /// Which process holds the lock, if the file names one.
    public static func holder(path: URL = SingleInstanceLock.defaultPath) -> Int32? {
        guard
            let contents = try? String(contentsOf: path, encoding: .utf8),
            let pid = Int32(contents.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return pid
    }
}
