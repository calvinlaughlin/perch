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
        //
        // The extra slack matters: the window origin has to be a whole point, but a camera housing
        // centred on a half point (185pt wide starting at 771) does not. Without room to spare, a
        // shape centred on the housing would sit half a point outside the canvas and get clipped.
        // A point of margin each side lets every shape be positioned on the hardware exactly.
        // Slack has to clear the shoulders, which flare outside the notch body, plus a point for
        // the whole-point rounding the window origin needs.
        let canvasSlack = max(1, options.shoulderRadius) + 1
        let expandedWidth = min(options.expandedWidth, screen.frame.width)
        let panelWidth = min(
            max(expandedWidth, collapsedWidth) + canvasSlack * 2,
            screen.frame.width
        )
        let panelHeight = notchSize.height + max(0, options.expandedHeight)

        // Centre the canvas on the notch, then nudge it back inside the display if that pushed it
        // off an edge (possible on a display whose housing is not centred, or with a huge bleed).
        let notchCentreX = notchMinX + notchSize.width / 2
        let unclampedMinX = notchCentreX - panelWidth / 2
        let panelMinX = min(
            max(unclampedMinX, screen.frame.minX),
            screen.frame.maxX - panelWidth
        )

        // The window origin must land on whole points, not merely whole backing pixels. AppKit
        // rounds window origins to integers, so an x of 653.5 silently becomes 653.0 and every
        // shape inside inherits a half-point leftward shift against the hardware it is tracing.
        // Rounding here — and then measuring the local rects against the *rounded* origin — keeps
        // what we compute and what the window server does in agreement.
        let panelRect = CGRect(
            x: panelMinX.rounded(),
            // AppKit: y grows upward, so the top edge of the display is maxY.
            y: (screen.frame.maxY - panelHeight).rounded(),
            width: snap(panelWidth, scale: scale),
            height: snap(panelHeight, scale: scale)
        )

        // --- Shapes, converted into the panel's local top-left-origin space -------------------
        // Views consume these, and SwiftUI's y axis points down, so both shapes hang from y = 0.
        // Offsets are relative to the rounded panel origin, so any rounding applied above is
        // absorbed here rather than displacing the shape.
        let collapsedRect = CGRect(
            x: snap(collapsedMinX - panelRect.minX, scale: scale),
            y: 0,
            width: snap(collapsedWidth, scale: scale),
            height: snap(notchSize.height, scale: scale)
        )

        // The physical housing, independent of any bleed. Views compare the shape they are about
        // to draw against this to decide whether it is tracing hardware.
        let hardwareRect = CGRect(
            x: snap(notchMinX - panelRect.minX, scale: scale),
            y: 0,
            width: snap(notchSize.width, scale: scale),
            height: snap(notchSize.height, scale: scale)
        )

        // Expanded is centred on the *housing*, not on the canvas, and spans the full canvas
        // height: it covers the notch and continues below it, which is what makes the shape read
        // as "growing out of" the notch. Centring on the canvas instead would put the two shapes
        // half a point apart whenever the housing centre is not a whole point, and the notch would
        // visibly slide sideways as it opened.
        let expandedRect = CGRect(
            x: snap(notchCentreX - expandedWidth / 2 - panelRect.minX, scale: scale),
            y: 0,
            width: snap(expandedWidth, scale: scale),
            height: panelRect.height
        )

        return NotchLayout(
            kind: kind,
            panelRect: panelRect,
            collapsedRect: collapsedRect,
            expandedRect: expandedRect,
            hardwareRect: hardwareRect,
            scale: scale
        )
    }

    /// Snap a length to whole backing pixels so edges stay crisp on Retina.
    private static func snap(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }
}
