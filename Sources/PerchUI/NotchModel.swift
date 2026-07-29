import Foundation
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

    /// What the notch is currently showing.
    public var state: NotchState = .collapsed

    /// The config currently in effect.
    ///
    /// Held here so views read radii and debug flags straight from the schema rather than through
    /// a parallel set of view properties that could drift out of sync with it.
    public var config: Config

    /// Which expanded widget is currently shown, indexed into `WidgetHost.widgets(at: .expanded)`.
    ///
    /// The expanded panel shows one widget at a time and scrolls vertically between them, so this
    /// is what "the current page" means. Kept in-memory across close→reopen so the notch returns
    /// to whatever the user was last looking at rather than snapping back to the top every time.
    /// Bounds-checking lives at the read site — the widget list can shrink under a config reload.
    public var expandedPageIndex: Int = 0

    public init(layout: NotchLayout, config: Config = Config()) {
        self.layout = layout
        self.config = config
    }

    /// Whether the notch is showing more than the bare hardware shape.
    public var isOpen: Bool { state != .collapsed }

    /// The shape being drawn right now, in the panel's local coordinate space.
    ///
    public var activeRect: CGRect {
        switch state {
        case .collapsed: layout.collapsedRect
        case .peek: layout.peekRect
        case .expanded: layout.expandedRect
        }
    }

    /// Whether the notch is showing an announcement rather than a panel the user opened.
    public var isPeeking: Bool { state == .peek }

    /// Accumulated scroll delta since the last page change.
    ///
    /// A trackpad flick fires dozens of `scrollWheel` events; a wheel fires a few. Both need to
    /// resolve to a single page change per gesture, and both keep coming during momentum. Holding
    /// the running total on the model lets the pager consume it in whole pages and reset the rest.
    /// Reset every time the direction reverses, so a small nudge back never sticks around and
    /// eats a later scroll the other way.
    public var expandedScrollAccumulator: CGFloat = 0
}
