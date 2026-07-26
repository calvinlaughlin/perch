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
}
