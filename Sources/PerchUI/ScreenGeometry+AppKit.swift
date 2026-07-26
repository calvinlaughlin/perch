import AppKit
import PerchCore

extension ScreenGeometry {
    /// Flatten an `NSScreen` into plain data.
    ///
    /// This is the only place AppKit's screen model touches perch's geometry, which is what keeps
    /// `NotchMetrics` testable — everything past this initializer is arithmetic over structs.
    public init(screen: NSScreen) {
        // `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` are nil on displays with no camera
        // housing. Zero widths make `hasHardwareNotch` false and route us to the synthetic pill.
        self.init(
            frame: screen.frame,
            safeAreaTopInset: screen.safeAreaInsets.top,
            auxiliaryTopLeftWidth: screen.auxiliaryTopLeftArea?.width ?? 0,
            auxiliaryTopRightWidth: screen.auxiliaryTopRightArea?.width ?? 0,
            backingScaleFactor: screen.backingScaleFactor
        )
    }
}

extension NSScreen {
    /// The screen perch should live on, honouring the `display` setting.
    ///
    /// Preferring the notched display by default means plugging in an external monitor does not
    /// yank the panel off the built-in screen just because the external one became `main`.
    ///
    /// An unmatched name falls back rather than failing: a config naming a monitor that is not
    /// plugged in right now should leave perch somewhere visible, not nowhere.
    public static func preferredScreen(matching preference: String = "notched") -> NSScreen? {
        switch preference.lowercased() {
        case "notched", "":
            return notchedScreen
        case "main":
            return main ?? notchedScreen
        default:
            let named = screens.first {
                $0.localizedName.localizedCaseInsensitiveContains(preference)
            }
            return named ?? notchedScreen
        }
    }

    /// A display with a real camera housing, else the main one, else anything at all.
    public static var notchedScreen: NSScreen? {
        screens.first { ScreenGeometry(screen: $0).hasHardwareNotch } ?? main ?? screens.first
    }
}
