import AppKit
import SwiftUI

/// A SwiftUI host that only sees mouse events inside the shape currently being drawn.
///
/// The panel's frame is fixed at the fully-expanded size, so most of the time the window covers a
/// large rectangle of screen that is visually empty. Without this, that empty region would swallow
/// every click landing near the top of the display. Restricting hit testing and mouse tracking to
/// `interactiveRect` makes the transparent area behave like it isn't there.
final class NotchHostingView<Content: View>: NSHostingView<Content> {

    /// The region that accepts mouse events, in SwiftUI's coordinate space.
    ///
    /// Origin top-left, y increasing downward. Everything outside it is click-through.
    var interactiveRect: CGRect = .zero {
        didSet {
            guard interactiveRect != oldValue else { return }
            refreshTrackingArea()
        }
    }

    /// Where a click toggles the notch instead of reaching the content.
    ///
    /// Everywhere else, clicks go to SwiftUI. Without this distinction the notch swallows every
    /// click — buttons never fire, and pressing one closes the panel instead. Nothing in a
    /// screenshot reveals that, which is why it survived a "verified working" claim.
    var toggleRect: CGRect = .zero

    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?
    var onClick: (() -> Void)?

    /// Builds the menu shown on right-click.
    ///
    /// Nil means no menu.
    var makeMenu: (() -> NSMenu)?

    private var notchTrackingArea: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` arrives in the superview's space; get it into ours first.
        let local = convert(point, from: superview)
        guard interactiveRect.contains(layoutPoint(fromViewPoint: local)) else { return nil }
        return super.hitTest(point)
    }

    /// Accept the very first click without perch having to become the active app.
    ///
    /// Without this the first click on the notch would only bring the panel forward and be
    /// swallowed, so every interaction would need two clicks.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard toggleRect.contains(layoutPoint(fromViewPoint: local)) else {
            // Forward to SwiftUI. `super` is what drives its gesture handling — SwiftUI does not
            // create NSView subviews for buttons, so swallowing the event here makes them inert.
            super.mouseDown(with: event)
            return
        }
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        // Only inside the shape. Elsewhere the panel is transparent and a menu there would come
        // from something the user cannot see.
        let local = convert(event.locationInWindow, from: nil)
        guard interactiveRect.contains(layoutPoint(fromViewPoint: local)),
            let menu = makeMenu?()
        else {
            super.rightMouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        // Resizing the tracking area under a stationary pointer — which happens on every
        // expand — makes AppKit report an exit the user never performed. Verify against the
        // pointer's actual position before believing it.
        guard !interactiveRectContainsPointer() else { return }
        onPointerExited?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refreshTrackingArea()
    }

    // MARK: - Tracking

    private func refreshTrackingArea() {
        if let notchTrackingArea {
            removeTrackingArea(notchTrackingArea)
            self.notchTrackingArea = nil
        }

        guard !interactiveRect.isEmpty else { return }

        let area = NSTrackingArea(
            rect: viewRect(fromLayoutRect: interactiveRect),
            // `.activeAlways` because perch is an accessory app and is never the active one; the
            // default active-when-key would mean the notch never responds to anything.
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        )
        addTrackingArea(area)
        notchTrackingArea = area
    }

    private func interactiveRectContainsPointer() -> Bool {
        guard let window else { return false }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        return interactiveRect.contains(layoutPoint(fromViewPoint: convert(inWindow, from: nil)))
    }

    // MARK: - Coordinate conversion

    /// Convert a point from the view's space into SwiftUI's.
    ///
    /// AppKit's y axis points up unless the view is flipped; `interactiveRect` is always expressed
    /// the way SwiftUI lays things out.
    private func layoutPoint(fromViewPoint point: NSPoint) -> NSPoint {
        isFlipped ? point : NSPoint(x: point.x, y: bounds.height - point.y)
    }

    private func viewRect(fromLayoutRect rect: CGRect) -> CGRect {
        guard !isFlipped else { return rect }
        return CGRect(
            x: rect.minX,
            y: bounds.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
