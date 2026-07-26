import AppKit
import PerchCore
import PerchUI

/// Wires the app together and owns the top-level objects.
///
/// Kept deliberately thin: it decides *what* exists, not *how* anything works. Config loading and
/// widget registration will hang off `applicationDidFinishLaunching` alongside the controller.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var notchController: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = NotchController()
        controller.start()
        notchController = controller
    }

    func applicationWillTerminate(_ notification: Notification) {
        notchController?.stop()
        notchController = nil
    }

    /// perch is ambient — closing whatever windows might exist should never quit it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
