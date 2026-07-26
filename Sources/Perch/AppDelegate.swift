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
        var config = Config()

        // Temporary bootstrap. Until the config file parser lands this env var is the only way to
        // reach `debug-shape`; it goes away once `debug-shape = true` in the config file works.
        if ProcessInfo.processInfo.environment["PERCH_DEBUG_SHAPE"] == "1" {
            config.debugShape = true
        }

        let controller = NotchController(config: config)
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
