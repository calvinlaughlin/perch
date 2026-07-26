import PerchCore
import SwiftUI

/// Observable state backing the notch view.
///
/// Uses `@Observable` rather than `ObservableObject` so SwiftUI invalidates only the views that
/// actually read a changed property. With media metadata ticking on every playback update, blanket
/// `objectWillChange` invalidation would redraw the whole tree several times a second.
@MainActor
@Observable
public final class NotchModel {

    /// Resolved geometry for the display perch is currently on.
    public var layout: NotchLayout

    /// Whether the notch is currently showing its expanded body.
    public var isExpanded: Bool = false

    /// Draw the shape tinted and outlined instead of black.
    ///
    /// The notch is physically black and so is the shape, which makes the collapsed state
    /// invisible by design and impossible to eyeball. Set `PERCH_DEBUG_SHAPE=1` to see exactly
    /// what geometry is being drawn. Folds into the config file as a `debug.shape` key later.
    public var debugShape: Bool = ProcessInfo.processInfo.environment["PERCH_DEBUG_SHAPE"] == "1"

    public init(layout: NotchLayout) {
        self.layout = layout
    }

    /// The shape being drawn right now, in the panel's local coordinate space.
    public var activeRect: CGRect {
        isExpanded ? layout.expandedRect : layout.collapsedRect
    }
}
