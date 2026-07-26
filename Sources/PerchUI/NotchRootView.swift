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
            topRadius: model.isExpanded ? 12 : 6,
            bottomRadius: model.isExpanded ? 24 : 14
        )
        let overhang = shape.horizontalOverhang

        shape
            .fill(.black)
            // Widen the frame so the shoulders have somewhere to render, then shift left by the
            // same amount so the notch body still lands exactly on the hardware.
            .frame(width: rect.width + overhang * 2, height: rect.height)
            .offset(x: rect.minX - overhang, y: rect.minY)
            // Pin to the top-leading corner so `offset` is measured from the panel's top-left,
            // which is the space `NotchLayout` expresses its rects in.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea()
    }
}
