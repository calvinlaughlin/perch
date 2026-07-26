import AppKit
import PerchCore
import PerchUI

/// Wires the app together and owns the top-level objects.
///
/// Kept deliberately thin: it decides *what* exists, not *how* anything works.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var notchController: NotchController?
    private var configWatcher: ConfigWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load before the panel exists, so the notch is never briefly drawn with the defaults and
        // then corrected — that flash is visible, and it happens on every launch.
        let initial = ConfigLoader.load(contentsOf: ConfigPaths.configFile)
        Self.report(initial)

        let controller = NotchController(config: initial.config)
        controller.start()
        notchController = controller
        Self.report(controller.widgetDiagnostics)

        let watcher = ConfigWatcher { [weak controller] result in
            Self.report(result)
            controller?.apply(config: result.config)
            Self.report(controller?.widgetDiagnostics ?? [])
        }
        watcher.start()
        configWatcher = watcher
    }

    func applicationWillTerminate(_ notification: Notification) {
        configWatcher?.stop()
        configWatcher = nil
        notchController?.stop()
        notchController = nil
    }

    /// perch is ambient — closing whatever windows might exist should never quit it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Surface config problems without ever refusing to run.
    private static func report(_ result: ConfigLoadResult) {
        for diagnostic in result.diagnostics {
            Log.config.error(diagnostic.description)
        }
        if result.diagnostics.isEmpty {
            Log.config.info("loaded \(ConfigPaths.display(ConfigPaths.configFile))")
        }
    }

    /// Surface widget problems, which are found after parsing rather than during it.
    private static func report(_ diagnostics: [Diagnostic]) {
        for diagnostic in diagnostics {
            Log.widget.error(diagnostic.description)
        }
    }
}
