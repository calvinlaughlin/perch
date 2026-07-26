import AppKit
import PerchCore
import ServiceManagement

/// Whether macOS starts perch at login.
///
/// Deliberately *not* a config key. This state lives in macOS's login-item database, and the user
/// can change it from System Settings at any time. A key in perch's config file would be a second
/// source of truth that silently disagrees with the first the moment they do — so perch reads and
/// writes the real thing and never caches its own answer.
///
/// Uses `SMAppService`, which registers the app bundle itself. The older approach needed a
/// separate helper bundle inside the app; this needs nothing but a correctly-signed bundle.
@MainActor
public enum LoginItem {

    /// What macOS currently thinks.
    public enum Status: Equatable, Sendable {
        case enabled
        case disabled

        /// Registered, but the user has to approve it in System Settings.
        ///
        /// macOS puts new login items here rather than trusting an app to enable itself silently.
        case awaitingApproval

        /// The app is somewhere macOS will not register from — typically a build directory.
        case unavailable
    }

    public static var status: Status {
        // Registering from anywhere but /Applications tends to fail, or to register a path that
        // stops existing on the next `make`. Say so plainly instead of offering a switch that
        // quietly does nothing.
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else { return .unavailable }

        return switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .awaitingApproval
        case .notRegistered, .notFound: .disabled
        @unknown default: .disabled
        }
    }

    /// Turn it on or off.
    public static func setEnabled(_ enabled: Bool) {
        guard status != .unavailable else {
            Log.config.error(
                "cannot manage login items: perch is running from \(Bundle.main.bundlePath), "
                    + "not /Applications. Run `make install` first."
            )
            return
        }

        do {
            if enabled {
                // Re-register from scratch rather than registering over an existing entry.
                // macOS can otherwise keep a login item pointing at the bundle path recorded when
                // it was first registered, and `make install` replaces the bundle wholesale — so
                // the entry would survive pointing at something that no longer exists. Rectangle
                // does the same for the same reason.
                if SMAppService.mainApp.status == .enabled {
                    try? SMAppService.mainApp.unregister()
                }
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    Log.config.info("login item added; approve it in System Settings")
                    openLoginItemsSettings()
                } else {
                    Log.config.info("perch will start at login")
                }
            } else {
                try SMAppService.mainApp.unregister()
                Log.config.info("perch will no longer start at login")
            }
        } catch {
            Log.config.error("could not change login item: \(error.localizedDescription)")
        }
    }

    /// Show the pane where the user approves or removes login items.
    public static func openLoginItemsSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
