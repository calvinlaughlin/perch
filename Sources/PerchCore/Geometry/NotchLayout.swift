import CoreGraphics

/// The resolved geometry perch draws with, in two coordinate spaces.
///
/// Every rectangle here is derived once per display change and then treated as immutable. The
/// window never resizes to follow the animation — `panelRect` is the fixed canvas, and the
/// collapsed/expanded shapes are drawn *within* it. Resizing an `NSWindow` per frame is the
/// classic source of notch-app jank; this type exists to make that mistake impossible.
public struct NotchLayout: Equatable, Sendable {
    /// Whether the shape traces real hardware or a synthesized pill.
    public enum Kind: Equatable, Sendable {
        /// The display has a camera housing; `notchRect` matches it exactly.
        case hardware
        /// No camera housing; `notchRect` is a synthetic pill hanging from the top edge.
        case synthetic
    }

    public var kind: Kind

    /// The fixed window frame, in global screen coordinates.
    ///
    /// Sized to contain the fully expanded shape with room to spare, and pinned flush to the top
    /// of the display.
    public var panelRect: CGRect

    /// The collapsed shape, in `panelRect`-local coordinates (origin top-left, y down — SwiftUI's
    /// space, since this is what views consume).
    public var collapsedRect: CGRect

    /// The expanded shape, in `panelRect`-local coordinates (origin top-left, y down).
    public var expandedRect: CGRect

    /// The physical camera housing, in `panelRect`-local coordinates.
    ///
    /// Equals `collapsedRect` when `collapsed-bleed` is zero. Views compare the shape they are
    /// about to draw against this to tell whether it is tracing hardware — a shape that exactly
    /// covers the housing must not draw shoulders, because there is nothing to blend into and
    /// they would just paint onto the menu bar either side of the notch.
    public var hardwareRect: CGRect

    /// Backing scale of the display this layout was resolved for.
    public var scale: CGFloat

    public init(
        kind: Kind,
        panelRect: CGRect,
        collapsedRect: CGRect,
        expandedRect: CGRect,
        hardwareRect: CGRect,
        scale: CGFloat
    ) {
        self.kind = kind
        self.panelRect = panelRect
        self.collapsedRect = collapsedRect
        self.expandedRect = expandedRect
        self.hardwareRect = hardwareRect
        self.scale = scale
    }

    /// Whether `rect` covers the camera housing exactly, so shoulders would spill onto the menu bar.
    public func tracesHardware(_ rect: CGRect) -> Bool {
        kind == .hardware && abs(rect.width - hardwareRect.width) < 0.5
    }
}

/// Tunables for how the notch shape is built.
///
/// Populated from config; the defaults are chosen to look correct on a 14"/16" MacBook Pro with
/// no configuration at all.
public struct NotchGeometryOptions: Equatable, Sendable {
    /// Height of the expanded panel *below* the notch, in points.
    public var expandedHeight: CGFloat

    /// Width of the expanded panel.
    ///
    /// Clamped to the display width at resolve time.
    public var expandedWidth: CGFloat

    /// Extra width added to each side of the collapsed shape.
    ///
    /// Lets widgets spill into the dead space beside the camera housing. Zero means "trace the
    /// hardware exactly".
    public var collapsedSideBleed: CGFloat

    /// Size of the synthetic pill used on displays with no camera housing.
    public var syntheticNotchSize: CGSize

    public init(
        expandedHeight: CGFloat = 180,
        expandedWidth: CGFloat = 420,
        collapsedSideBleed: CGFloat = 0,
        syntheticNotchSize: CGSize = CGSize(width: 200, height: 32)
    ) {
        self.expandedHeight = expandedHeight
        self.expandedWidth = expandedWidth
        self.collapsedSideBleed = collapsedSideBleed
        self.syntheticNotchSize = syntheticNotchSize
    }

    public static let `default` = NotchGeometryOptions()
}
