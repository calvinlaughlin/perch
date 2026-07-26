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
    /// The screen perch should live on: the one with a real camera housing, else the main screen.
    ///
    /// Preferring the notched display means plugging in an external monitor doesn't yank the panel
    /// off the built-in screen just because the external one became `main`.
    public static var preferredNotchScreen: NSScreen? {
        screens.first { ScreenGeometry(screen: $0).hasHardwareNotch } ?? main ?? screens.first
    }
}
