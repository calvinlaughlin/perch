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

        // No key equivalents. A context menu displays them, which would advertise shortcuts that
        // do not exist — perch is an accessory app and never holds focus, so nothing here can be
        // reached from the keyboard. Showing "⌘," beside Edit Configuration would promise exactly
        // the binding this app deliberately does not take from other apps.
        menu.addItem(ActionItem(title: "Edit Configuration…") { openConfiguration() })
        menu.addItem(ActionItem(title: "Reload Configuration") { reload() })

        menu.addItem(.separator())

        menu.addItem(
            ActionItem(title: "Reveal Configuration in Finder") {
                let file = ConfigPaths.ensureConfigFileExists()
                NSWorkspace.shared.activateFileViewerSelecting([file])
            })

        menu.addItem(.separator())
        menu.addItem(loginItem())
        menu.addItem(.separator())
        menu.addItem(ActionItem(title: "Quit perch") { quit() })

        return menu
    }

    /// A toggle reflecting whatever macOS currently thinks, not what perch last set.
    ///
    /// Built fresh each time the menu opens, so it stays right even when the user changes it in
    /// System Settings behind perch's back.
    private static func loginItem() -> NSMenuItem {
        switch LoginItem.status {
        case .unavailable:
            let item = NSMenuItem(
                title: "Open at Login (install to enable)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item

        case .awaitingApproval:
            let item = ActionItem(title: "Open at Login — approve in Settings…") {
                LoginItem.openLoginItemsSettings()
            }
            item.state = .mixed
            return item

        case .enabled, .disabled:
            let isOn = LoginItem.status == .enabled
            let item = ActionItem(title: "Open at Login") { LoginItem.setEnabled(!isOn) }
            item.state = isOn ? .on : .off
            return item
        }
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

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not supported") }

    @objc private func run() { handler() }
}
