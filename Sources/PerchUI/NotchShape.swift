import SwiftUI

/// The silhouette of the notch: square where it meets the top of the display, rounded where it
/// hangs into the screen, with a small concave flare on each shoulder.
///
/// That flare is what sells the illusion. Without it the shape reads as a floating rectangle
/// pasted near the top of the screen; with it, the shape appears to be carved out of the bezel
/// and the hardware housing blends into whatever we draw.
public struct NotchShape: Shape {
    /// Radius of the concave shoulders where the shape meets the top edge.
    public var topRadius: CGFloat
    /// Radius of the convex bottom corners.
    public var bottomRadius: CGFloat

    public init(topRadius: CGFloat = 6, bottomRadius: CGFloat = 14) {
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
    }

    /// Animate the two radii together so the shape morphs smoothly between states.
    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    /// Horizontal padding a view must add around the notch body to leave room for the shoulders.
    ///
    /// The shoulders flare *outward* from the notch, so a view sized to the bare notch would have
    /// them clipped off. Callers widen the frame by this much on each side and the shape insets
    /// itself back to the true notch bounds.
    public var horizontalOverhang: CGFloat { max(0, topRadius) }

    public func path(in rect: CGRect) -> Path {
        // `rect` is the full bounding box including the shoulder overhang on each side. Inset to
        // recover the notch body itself, so everything below is expressed in hardware terms.
        let top = max(0, min(topRadius, min(rect.width / 4, rect.height)))
        let body = rect.insetBy(dx: top, dy: 0)

        // Keep the bottom corners physically possible for the body we ended up with.
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
