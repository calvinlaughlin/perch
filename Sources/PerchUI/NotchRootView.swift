import PerchCore
import SwiftUI

/// The whole visual surface of perch.
///
/// The view fills the fixed panel and positions the notch shape inside it, rather than the window
/// resizing to match the shape. Expanding is therefore a pure layout change in SwiftUI — no
/// window-server round trip per frame, which is what keeps the animation smooth.
public struct NotchRootView: View {

    private let model: NotchModel

    public init(model: NotchModel) {
        self.model = model
    }

    public var body: some View {
        let rect = model.activeRect
        let shape = NotchShape(
            topRadius: model.isOpen ? 12 : 6,
            bottomRadius: model.isOpen
                ? model.config.cornerRadius
                : model.config.collapsedCornerRadius
        )
        let overhang = shape.horizontalOverhang

        fill(shape)
            // Widen the frame so the shoulders have somewhere to render, then shift left by the
            // same amount so the notch body still lands exactly on the hardware.
            .frame(width: rect.width + overhang * 2, height: rect.height)
            .offset(x: rect.minX - overhang, y: rect.minY)
            // Pin to the top-leading corner so `offset` is measured from the panel's top-left,
            // which is the space `NotchLayout` expresses its rects in.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Slightly overdamped: the notch is a physical object on the bezel, and overshoot
            // reads as wobble rather than liveliness at this size.
            .animation(.spring(response: 0.34, dampingFraction: 0.82), value: model.state)
            .ignoresSafeArea()
    }

    /// Black in normal use; tinted and outlined when inspecting geometry.
    @ViewBuilder
    private func fill(_ shape: NotchShape) -> some View {
        if model.config.debugShape {
            shape
                .fill(.red.opacity(0.45))
                .overlay(shape.stroke(.white, lineWidth: 1))
        } else {
            shape.fill(.black)
        }
    }
}
