import Foundation
import Testing

@testable import PerchCore

@Suite("Locating the running bundle")
struct RunningBundleTests {

    /// A throwaway `<name>.app/Contents/MacOS/<exe>` on disk, plus somewhere to symlink it from.
    ///
    /// Built for real rather than faked with string manipulation because the bug being guarded
    /// against is entirely about what happens on disk: `resolvingSymlinksInPath` has nothing to
    /// resolve unless there is a genuine symlink to a genuine file.
    private struct Fixture: ~Copyable {
        let root: URL
        let app: URL
        let executable: URL
        let linkDirectory: URL

        init() throws {
            root = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("perch-bundle-\(UUID().uuidString)")
            app = root.appendingPathComponent("perch.app")
            executable = app.appendingPathComponent("Contents/MacOS/perch")
            linkDirectory = root.appendingPathComponent("bin")

            try FileManager.default.createDirectory(
                at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: linkDirectory, withIntermediateDirectories: true)
            try Data().write(to: executable)
        }

        /// A symlink to the executable, the way Homebrew's `binary` stanza links it onto PATH.
        func symlink(named name: String = "perch") throws -> URL {
            let link = linkDirectory.appendingPathComponent(name)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: executable)
            return link
        }

        deinit { try? FileManager.default.removeItem(at: root) }
    }

    @Test("An executable inside a bundle resolves to the bundle")
    func executableInsideBundle() throws {
        let fixture = try Fixture()

        let found = Bundle.appBundleURL(containingExecutable: fixture.executable)

        #expect(found?.resolvingSymlinksInPath() == fixture.app.resolvingSymlinksInPath())
    }

    @Test("A symlink onto PATH still resolves to the bundle")
    func symlinkResolvesToBundle() throws {
        // The actual regression. Homebrew links the executable into /opt/homebrew/bin, and every
        // lookup through Bundle.main then reads a directory that has no Info.plist and no
        // Resources — costing the version string and, worse, the media adapter.
        let fixture = try Fixture()
        let link = try fixture.symlink()

        let found = Bundle.appBundleURL(containingExecutable: link)

        #expect(found?.resolvingSymlinksInPath() == fixture.app.resolvingSymlinksInPath())
    }

    @Test("A bare executable is not inside a bundle")
    func looseExecutable() throws {
        let fixture = try Fixture()
        let loose = fixture.linkDirectory.appendingPathComponent("perch")
        try Data().write(to: loose)

        #expect(Bundle.appBundleURL(containingExecutable: loose) == nil)
    }

    @Test("Three levels below something merely ending in .app is not a bundle")
    func lookalikeLayoutIsRejected() throws {
        // Walking up three components would accept this. The layout is matched exactly instead,
        // so a directory that happens to end in `.app` cannot masquerade as one.
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perch-lookalike-\(UUID().uuidString)")
        let executable = root.appendingPathComponent("notes.app/Documents/Drafts/perch")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: executable)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(Bundle.appBundleURL(containingExecutable: executable) == nil)
    }

    @Test("A real bundle is left alone")
    func realBundleIsUnchanged() {
        // Launched normally there is nothing to resolve, and resolving anyway would be a way to
        // get it wrong. Bundle.main here is the test runner, which is itself a bundle.
        let resolved = Bundle.resolveRunning(from: .main)

        #expect(resolved == Bundle.main)
    }
}
