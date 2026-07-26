import PerchCore
import SwiftUI

/// Lays widgets out inside the notch shape.
///
/// Content is positioned against the same rects the shape is drawn from, so it tracks the notch
/// exactly rather than being laid out by SwiftUI independently and hoping the two agree.
struct NotchContentView: View {

    let model: NotchModel
    let host: WidgetHost

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The strip is always present. It lives in the dead space beside the camera housing,
            // which does not go away when the panel opens — and fading it with the panel is
            // exactly the bug that meant strip widgets never appeared at all.
            collapsedStrip
                .opacity(model.isOpen ? 0 : 1)

            expandedContent
                // Fades on the same spring as the shape, so the open panel reads as one surface
                // arriving rather than a background followed by its contents.
                .opacity(model.isOpen ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Expanded

    /// Widgets in the body of the open panel, below the camera housing.
    private var expandedContent: some View {
        let rect = model.layout.expandedRect
        let housingHeight = model.layout.hardwareRect.height
        let inset: CGFloat = 10

        return HStack(spacing: inset) {
            ForEach(Array(host.widgets(at: .expanded).enumerated()), id: \.offset) { _, widget in
                widget.body
            }
        }
        .frame(
            width: max(0, rect.width - inset * 2),
            // Start below the housing: content drawn behind it is content nobody can see.
            height: max(0, rect.height - housingHeight - inset)
        )
        .position(
            x: rect.midX,
            y: housingHeight + (rect.height - housingHeight) / 2
        )
    }

    // MARK: - Collapsed

    /// Widgets in the strips either side of the camera housing.
    ///
    /// These have room only when `collapsed-bleed` is non-zero; at zero the collapsed shape traces
    /// the housing exactly and there is nowhere to draw that is not behind it.
    private var collapsedStrip: some View {
        let collapsed = model.layout.collapsedRect
        let housing = model.layout.hardwareRect
        let leadingWidth = max(0, housing.minX - collapsed.minX)
        let trailingWidth = max(0, collapsed.maxX - housing.maxX)

        return ZStack(alignment: .topLeading) {
            if leadingWidth > 0 {
                strip(host.widgets(at: .leading), alignment: .trailing)
                    .frame(width: leadingWidth, height: collapsed.height)
                    .position(x: collapsed.minX + leadingWidth / 2, y: collapsed.height / 2)
            }
            if trailingWidth > 0 {
                strip(host.widgets(at: .trailing), alignment: .leading)
                    .frame(width: trailingWidth, height: collapsed.height)
                    .position(x: housing.maxX + trailingWidth / 2, y: collapsed.height / 2)
            }
        }
    }

    private func strip(_ widgets: [any NotchWidget], alignment: Alignment) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(widgets.enumerated()), id: \.offset) { _, widget in
                widget.body
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .padding(.horizontal, 6)
    }
}
