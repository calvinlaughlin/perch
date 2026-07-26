import CoreGraphics

/// Turns a display into the rectangles perch draws with.
///
/// Pure arithmetic — no AppKit, no global state, no I/O. This is deliberately the only place that
/// knows how notch geometry is computed, so the rules live in one readable function and the tests
/// can exercise every display shape without needing the hardware.
public enum NotchMetrics {

    /// Resolve the drawing geometry for a display.
    ///
    /// Displays with a camera housing get a shape that traces the hardware exactly. Displays
    /// without one get a synthetic pill hanging from the top edge, so external monitors work
    /// through the same code path with no special-casing upstream.
    public static func resolve(
        for screen: ScreenGeometry,
        options: NotchGeometryOptions = .default
    ) -> NotchLayout {
        let scale = screen.backingScaleFactor > 0 ? screen.backingScaleFactor : 1

        // --- The collapsed shape, in global coordinates -------------------------------------
        let notchSize: CGSize
        let notchMinX: CGFloat
        let kind: NotchLayout.Kind

        if screen.hasHardwareNotch {
            // The camera housing is exactly the gap the auxiliary areas leave between them.
            let width =
                screen.frame.width
                - screen.auxiliaryTopLeftWidth
                - screen.auxiliaryTopRightWidth
            notchSize = CGSize(width: width, height: screen.safeAreaTopInset)
            notchMinX = screen.frame.minX + screen.auxiliaryTopLeftWidth
            kind = .hardware
        } else {
            notchSize = options.syntheticNotchSize
            notchMinX = screen.frame.midX - notchSize.width / 2
            kind = .synthetic
        }

        // Widgets may bleed sideways into the dead space next to the housing.
        let bleed = max(0, options.collapsedSideBleed)
        let collapsedWidth = notchSize.width + bleed * 2
        let collapsedMinX = notchMinX - bleed

        // --- The fixed window canvas ---------------------------------------------------------
        // Wide enough for whichever shape is larger, never wider than the display, and pinned
        // flush to the top edge. This frame does not change as the notch animates.
        let expandedWidth = min(options.expandedWidth, screen.frame.width)
        let panelWidth = min(max(expandedWidth, collapsedWidth), screen.frame.width)
        let panelHeight = notchSize.height + max(0, options.expandedHeight)

        // Centre the canvas on the notch, then nudge it back inside the display if that pushed it
        // off an edge (possible on a display whose housing is not centred, or with a huge bleed).
        let notchCentreX = notchMinX + notchSize.width / 2
        let unclampedMinX = notchCentreX - panelWidth / 2
        let panelMinX = min(
            max(unclampedMinX, screen.frame.minX),
            screen.frame.maxX - panelWidth
        )

        let panelRect = align(
            CGRect(
                x: panelMinX,
                y: screen.frame.maxY - panelHeight,  // AppKit: y grows upward, so top edge is maxY
                width: panelWidth,
                height: panelHeight
            ),
            scale: scale
        )

        // --- Shapes, converted into the panel's local top-left-origin space -------------------
        // Views consume these, and SwiftUI's y axis points down, so both shapes hang from y = 0.
        let collapsedRect = align(
            CGRect(
                x: collapsedMinX - panelRect.minX,
                y: 0,
                width: collapsedWidth,
                height: notchSize.height
            ),
            scale: scale
        )

        // Expanded is centred in the canvas and spans the full canvas height: it covers the notch
        // and continues below it, which is what makes the shape read as "growing out of" the notch.
        let expandedRect = align(
            CGRect(
                x: (panelRect.width - expandedWidth) / 2,
                y: 0,
                width: expandedWidth,
                height: panelRect.height
            ),
            scale: scale
        )

        return NotchLayout(
            kind: kind,
            panelRect: panelRect,
            collapsedRect: collapsedRect,
            expandedRect: expandedRect,
            scale: scale
        )
    }

    /// Snap a rect to whole backing pixels so edges stay crisp on Retina.
    private static func align(_ rect: CGRect, scale: CGFloat) -> CGRect {
        func snap(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        return CGRect(
            x: snap(rect.origin.x),
            y: snap(rect.origin.y),
            width: snap(rect.width),
            height: snap(rect.height)
        )
    }
}
