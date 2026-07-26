import PerchCore
import SwiftUI

/// The whole visual surface of perch.
///
/// The view fills the fixed panel and the shape draws itself at absolute coordinates within it,
/// rather than the window resizing or a sized frame being positioned to match. Expanding is
/// therefore a pure repaint — no window-server round trip per frame, and no layout frame whose
/// origin SwiftUI might round out from under us.
public struct NotchRootView: View {

    private let model: NotchModel

    public init(model: NotchModel) {
        self.model = model
    }

    public var body: some View {
        let rect = model.activeRect

        // A shape that exactly covers the camera housing is entirely hidden behind it, so its
        // shoulders would be the only visible part — black wedges on the menu bar either side of
        // the notch. Drop them, and let them grow back in as the panel widens past the hardware.
        let shape = NotchShape(
            bodyRect: rect,
            topRadius: model.layout.tracesHardware(rect) ? 0 : model.config.shoulderRadius,
            bottomRadius: model.isOpen
                ? model.config.cornerRadius
                : model.config.collapsedCornerRadius
        )

        fill(shape)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
