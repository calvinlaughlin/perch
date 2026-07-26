import SwiftUI

/// The silhouette of the notch: square where it meets the top of the display, rounded where it
/// hangs into the screen, with a small concave flare on each shoulder.
///
/// That flare is what sells the illusion. Without it the shape reads as a floating rectangle
/// pasted near the top of the screen; with it, the shape appears to be carved out of the bezel
/// and the hardware housing blends into whatever we draw.
///
/// The shape draws at **absolute coordinates inside whatever canvas it is given**, rather than
/// filling its own frame. That is deliberate. The obvious alternative — size a frame to the notch
/// plus shoulder overhang, then offset or position it — puts a child larger than its container
/// into the layout system, and SwiftUI rounds such a frame's origin to whole points. On a display
/// whose camera housing is centred on a half point, that rounding silently shifted the panel by
/// half a point and, in another arrangement, clipped eight points off one side. Drawing absolutely
/// removes the frame, and with it the rounding.
public struct NotchShape: Shape {

    /// Where the notch body sits within the canvas.
    ///
    /// Shoulders flare *outside* this rect.
    public var bodyRect: CGRect

    /// Radius of the concave shoulders where the shape meets the top edge.
    public var topRadius: CGFloat

    /// Radius of the convex bottom corners.
    public var bottomRadius: CGFloat

    public init(bodyRect: CGRect, topRadius: CGFloat = 10, bottomRadius: CGFloat = 14) {
        self.bodyRect = bodyRect
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
    }

    /// Animate position, size, and both radii together so the shape morphs smoothly between states.
    public var animatableData:
        AnimatablePair<
            AnimatablePair<CGFloat, CGFloat>,
            AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>
        >
    {
        get {
            AnimatablePair(
                AnimatablePair(bodyRect.origin.x, bodyRect.width),
                AnimatablePair(bodyRect.height, AnimatablePair(topRadius, bottomRadius))
            )
        }
        set {
            bodyRect.origin.x = newValue.first.first
            bodyRect.size.width = newValue.first.second
            bodyRect.size.height = newValue.second.first
            topRadius = newValue.second.second.first
            bottomRadius = newValue.second.second.second
        }
    }

    public func path(in canvas: CGRect) -> Path {
        // `canvas` is only the drawing surface. Everything below is measured from `bodyRect`, so
        // the shape lands where the geometry said it should regardless of how it was framed.
        let body = bodyRect

        // Keep the radii physically possible for the body we were handed.
        let top = max(0, min(topRadius, min(body.width / 4, body.height)))
        let bottom = max(0, min(bottomRadius, min(body.width / 2, body.height - top)))

        var path = Path()

        // Start at the outer edge of the left shoulder, flush with the top.
        path.move(to: CGPoint(x: body.minX - top, y: body.minY))

        // Concave left shoulder, curving down and inward into the notch.
        path.addQuadCurve(
            to: CGPoint(x: body.minX, y: body.minY + top),
            control: CGPoint(x: body.minX, y: body.minY)
        )

        // Left edge down to where the bottom-left corner begins.
        path.addLine(to: CGPoint(x: body.minX, y: body.maxY - bottom))

        // Convex bottom-left corner.
        path.addQuadCurve(
            to: CGPoint(x: body.minX + bottom, y: body.maxY),
            control: CGPoint(x: body.minX, y: body.maxY)
        )

        // Bottom edge.
        path.addLine(to: CGPoint(x: body.maxX - bottom, y: body.maxY))

        // Convex bottom-right corner.
        path.addQuadCurve(
            to: CGPoint(x: body.maxX, y: body.maxY - bottom),
            control: CGPoint(x: body.maxX, y: body.maxY)
        )

        // Right edge back up to the shoulder.
        path.addLine(to: CGPoint(x: body.maxX, y: body.minY + top))

        // Concave right shoulder, mirroring the left.
        path.addQuadCurve(
            to: CGPoint(x: body.maxX + top, y: body.minY),
            control: CGPoint(x: body.maxX, y: body.minY)
        )

        path.closeSubpath()
        return path
    }
}
