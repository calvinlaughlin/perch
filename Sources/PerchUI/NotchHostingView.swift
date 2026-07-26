import AppKit
import SwiftUI

/// A SwiftUI host that only accepts clicks inside the shape currently being drawn.
///
/// The panel's frame is fixed at the fully-expanded size, so most of the time the window covers a
/// large rectangle of screen that is visually empty. Without this, that empty region would swallow
/// every click landing near the top of the display. Restricting hit testing to `interactiveRect`
/// makes the transparent area behave like it isn't there.
final class NotchHostingView<Content: View>: NSHostingView<Content> {

    /// The region that accepts mouse events, in SwiftUI's coordinate space.
    ///
    /// Origin top-left, y increasing downward. Everything outside it is click-through.
    var interactiveRect: CGRect = .zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` arrives in the superview's space; get it into ours first.
        let local = convert(point, from: superview)

        // AppKit's y axis points up unless the view is flipped, but `interactiveRect` is always
        // expressed the way SwiftUI lays things out. Normalise before comparing.
        let inLayoutSpace =
            isFlipped
            ? local
            : NSPoint(x: local.x, y: bounds.height - local.y)

        guard interactiveRect.contains(inLayoutSpace) else { return nil }
        return super.hitTest(point)
    }
}
