import CoreGraphics
import Foundation

/// Every user-settable option in perch.
///
/// This struct is the schema. Each stored property corresponds to one key in the config file, its
/// declared value is the default, and its doc comment is the user-facing documentation. Keeping
/// those three things in one place is what stops the file format, the code, and the docs from
/// drifting apart — and it is what makes `perch +show-config --default --docs` possible later.
///
/// Keys are flat and hyphenated (`open-delay`, not `notch.open.delay`). A flat namespace means one
/// grammar with no nesting rules, and per-widget options namespace themselves with a prefix
/// (`media-artwork`).
///
/// **Zero configuration must be good configuration.** The defaults below are what perch looks like
/// with no config file at all, and that has to be a state worth shipping — the file is for people
/// who disagree with a default, not a prerequisite for a working app.
public struct Config: Equatable, Sendable {

    // MARK: - Interaction

    /// What opens the notch: `hover`, `click`, or `never`.
    ///
    /// `never` leaves the notch inert to the pointer; widgets can still peek.
    public var openOn: OpenTrigger = .hover

    /// How long the pointer must rest on the notch before it opens.
    ///
    /// Guards against the notch flying open every time the pointer crosses the top of the screen
    /// on its way to the menu bar. Ignored when `open-on` is not `hover`.
    public var openDelay: Duration = .milliseconds(120)

    // MARK: - Shape

    /// Height of the expanded panel below the notch, in points.
    public var expandedHeight: CGFloat = 180

    /// Width of the expanded panel, in points.
    ///
    /// Clamped to the display width.
    public var expandedWidth: CGFloat = 420

    /// Corner radius of the expanded panel's bottom corners, in points.
    public var cornerRadius: CGFloat = 24

    /// Corner radius of the collapsed shape's bottom corners, in points.
    ///
    /// Defaults to roughly the curvature of the physical camera housing, so the collapsed state
    /// disappears into the hardware.
    public var collapsedCornerRadius: CGFloat = 14

    /// Extra width added to each side of the collapsed shape, in points.
    ///
    /// Lets widgets spill into the dead space beside the camera housing. `0` traces the hardware
    /// exactly.
    public var collapsedBleed: CGFloat = 0

    // MARK: - Debugging

    /// Draw the notch shape tinted and outlined instead of black.
    ///
    /// The notch is physically black and so is the shape, which makes the collapsed state
    /// impossible to eyeball. Turn this on to see exactly what geometry is being drawn.
    public var debugShape: Bool = false

    public init() {}

    /// The subset of config that `NotchMetrics` needs.
    ///
    /// Keeps the geometry layer's input a small explicit struct rather than the whole config, so
    /// adding an unrelated key can never change how geometry resolves.
    public var geometryOptions: NotchGeometryOptions {
        NotchGeometryOptions(
            expandedHeight: expandedHeight,
            expandedWidth: expandedWidth,
            collapsedSideBleed: collapsedBleed
        )
    }
}
