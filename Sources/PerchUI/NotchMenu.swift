import AppKit
import PerchCore

/// The menu shown when the notch is right-clicked.
///
/// perch has no dock icon, no menu bar item, and no window you can reach — the notch is its only
/// surface, so this is the only place these actions can live. Without it the only way to quit is
/// `pkill`, which is not something to ask of anyone who did not write the app.
///
/// Right-click specifically, because left-click already toggles the panel and widgets need it.
@MainActor
public enum NotchMenu {

    /// Build the menu. `reload` and `quit` are supplied by the controller.
    public static func make(
        reload: @escaping () -> Void,
        quit: @escaping () -> Void
    ) -> NSMenu {
        let menu = NSMenu()

        menu.addItem(
            ActionItem(title: "Edit Configuration…", key: ",") {
                openConfiguration()
            })
        menu.addItem(
            ActionItem(title: "Reload Configuration", key: "r") {
                reload()
            })

        menu.addItem(.separator())

        menu.addItem(
            ActionItem(title: "Reveal Configuration in Finder", key: "") {
                let file = ConfigPaths.ensureConfigFileExists()
                NSWorkspace.shared.activateFileViewerSelecting([file])
            })

        menu.addItem(.separator())
        menu.addItem(ActionItem(title: "Quit perch", key: "q") { quit() })

        return menu
    }

    /// Open the config in whatever the user edits text with.
    ///
    /// Creates the file first: opening a path that does not exist either fails silently or dumps
    /// the user into an empty buffer with no clue what belongs in it.
    public static func openConfiguration() {
        NSWorkspace.shared.open(ConfigPaths.ensureConfigFileExists())
    }
}

/// A menu item that runs a closure, so callers do not need a target/action pair.
private final class ActionItem: NSMenuItem {

    private let handler: () -> Void

    init(title: String, key: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not supported") }

    @objc private func run() { handler() }
}
