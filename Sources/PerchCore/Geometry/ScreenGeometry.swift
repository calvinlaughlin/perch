import CoreGraphics

/// A plain-data snapshot of everything `NotchMetrics` needs from a display.
///
/// `NSScreen` is impossible to construct in a test, so the AppKit layer flattens it into this
/// struct at the boundary (see `ScreenGeometry.init(screen:)` in PerchUI) and every geometry
/// decision downstream is pure arithmetic over values we can fabricate freely.
///
/// All rectangles use AppKit's global display coordinate space: origin bottom-left, y increasing
/// upward, and `frame.maxY` is the physical top edge of the display.
public struct ScreenGeometry: Equatable, Sendable {
    /// Full display bounds in global coordinates.
    public var frame: CGRect

    /// Height of the region at the top of the display that content must avoid.
    ///
    /// On a notched Mac this is the notch height (38pt on the 14"/16" MacBook Pro). It is `0` on
    /// displays without a camera housing — which is how we detect notchlessness.
    public var safeAreaTopInset: CGFloat

    /// Width of the usable strip to the *left* of the camera housing.
    ///
    /// Taken from `auxiliaryTopLeftArea`. Zero on displays with no notch.
    public var auxiliaryTopLeftWidth: CGFloat

    /// Width of the usable strip to the *right* of the camera housing.
    ///
    /// Taken from `auxiliaryTopRightArea`. Zero on displays with no notch.
    public var auxiliaryTopRightWidth: CGFloat

    /// Backing scale of the display, 2.0 on Retina.
    ///
    /// Used to snap geometry to whole pixels.
    public var backingScaleFactor: CGFloat

    public init(
        frame: CGRect,
        safeAreaTopInset: CGFloat,
        auxiliaryTopLeftWidth: CGFloat,
        auxiliaryTopRightWidth: CGFloat,
        backingScaleFactor: CGFloat
    ) {
        self.frame = frame
        self.safeAreaTopInset = safeAreaTopInset
        self.auxiliaryTopLeftWidth = auxiliaryTopLeftWidth
        self.auxiliaryTopRightWidth = auxiliaryTopRightWidth
        self.backingScaleFactor = backingScaleFactor
    }

    /// Whether this display has a real hardware camera housing.
    ///
    /// A notched display reports a non-zero top inset *and* auxiliary areas on both sides. Both
    /// halves matter: an external display can report a non-zero safe-area inset in some
    /// configurations without having a notch, and it would have no auxiliary areas.
    public var hasHardwareNotch: Bool {
        safeAreaTopInset > 0 && auxiliaryTopLeftWidth > 0 && auxiliaryTopRightWidth > 0
    }
}
