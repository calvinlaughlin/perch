import Testing

@testable import PerchUI

/// Whether the artwork leads anywhere, which is decided before anything is drawn.
///
/// The click itself cannot be tested here — it hands an app to Launch Services and the answer is
/// "some other app is now frontmost", which no unit test can see. `make ui-probe FULL=1` clicks the
/// real cover and checks the real frontmost app; this covers the half that decides whether there is
/// a button to click at all.
@MainActor
struct PlayerLinkTests {

    @Test("An installed app resolves to something openable")
    func resolvesInstalledApp() {
        // The Finder, because it is the one bundle identifier every Mac is guaranteed to have.
        let player = PlayerApp.resolve(bundleIdentifier: "com.apple.finder")

        #expect(player != nil)
        #expect(player?.url.pathExtension == "app")
        // The name shown, not the identifier: a tooltip reading "com.apple.finder" is a leak of
        // something the user never needs to see.
        #expect(player?.name == "Finder")
        #expect(player?.name.hasSuffix(".app") == false)
    }

    @Test("An identifier nothing claims resolves to nothing")
    func rejectsUnknownIdentifier() {
        // The case that decides the cover is a picture rather than a dead button: the system names
        // whatever is emitting audio, and that is not always an app you can open — a helper
        // process, or a player that has since been deleted.
        #expect(PlayerApp.resolve(bundleIdentifier: "dev.perch.no-such-app-exists") == nil)
        #expect(PlayerApp.resolve(bundleIdentifier: "") == nil)
    }
}
