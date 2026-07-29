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
                .animation(nil, value: model.state)

            // A peek shows the same widgets in a compact form: it is an announcement, so it
            // carries what changed and not the controls you would only want if you had asked.
            // Switched instantly, not faded. Text drawn at fractional opacity changes
            // antialiasing — subpixel to grayscale and back — which reads as the words shifting
            // and thickening while you are trying to read them. The shape still animates, and its
            // clip is what reveals the content, so the panel remains one surface arriving rather
            // than a background followed by its contents.
            peekContent
                .opacity(model.isPeeking ? 1 : 0)
                .animation(nil, value: model.state)

            expandedContent
                .opacity(model.state == .expanded ? 1 : 0)
                .animation(nil, value: model.state)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Expanded

    /// Widgets in the body of the open panel, below the camera housing.
    ///
    /// One widget is shown at a time; scrolling vertically inside the panel moves between them and
    /// the choice is remembered on `model.expandedPageIndex` so a close-and-reopen returns to the
    /// same one. That is the deliberate compromise for a panel this small: two widgets crammed
    /// side-by-side each get less than half the width, but one at a time gets the full row.
    private var expandedContent: some View {
        let rect = model.layout.expandedRect
        let housingHeight = model.layout.hardwareRect.height
        let inset: CGFloat = 10
        let widgets = host.widgets(at: .expanded)

        return ExpandedPager(model: model, widgets: widgets)
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

    /// Widgets in a peek: compact, centred, no controls.
    private var peekContent: some View {
        let rect = model.layout.peekRect
        let housingHeight = model.layout.hardwareRect.height
        let inset: CGFloat = 8

        return HStack(spacing: inset) {
            ForEach(Array(host.widgets(at: .expanded).enumerated()), id: \.offset) { _, widget in
                widget.peekBody
            }
        }
        .frame(
            width: max(0, rect.width - inset * 2),
            height: max(0, rect.height - housingHeight - inset)
        )
        // Biased slightly upward rather than centred. The shape's bottom corners are rounded, so
        // an optically centred row sits closer to the edge than it measures — a few points of
        // extra room underneath makes it look settled rather than cramped.
        .position(
            x: rect.midX,
            y: housingHeight + (rect.height - housingHeight) / 2 - peekBottomBias
        )
    }

    /// Extra breathing room beneath a peek's content.
    private let peekBottomBias: CGFloat = 4

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

// MARK: - Expanded pager

/// Shows one expanded widget at a time and switches between them on a vertical scroll.
///
/// The panel itself never resizes (see `NotchShape` comments), so a scrolling *pager* rather than
/// a scrolling *stack*: pages are the same size as the container, only one is on screen, and the
/// transition slides one out as the other slides in. That way the panel always looks full and the
/// user still gets to move between widgets without either being cropped.
private struct ExpandedPager: View {

    @Bindable var model: NotchModel
    let widgets: [any NotchWidget]

    var body: some View {
        // Read the currently-selected page and clamp: a config reload can remove a widget, and an
        // out-of-range index left over from the previous set must not crash the view.
        let count = max(widgets.count, 1)
        let index = min(max(model.expandedPageIndex, 0), max(widgets.count - 1, 0))

        return ZStack(alignment: .trailing) {
            if widgets.isEmpty {
                Color.clear
            } else {
                // A transition rather than a real scroll view: SwiftUI's ScrollView would try to
                // manage its own offset and paging feel, and a panel this small needs a single
                // sharp snap between widgets, not free scrolling.
                widgets[index].body
                    .id(index)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        )
                    )
            }

            if widgets.count > 1 {
                pageIndicator(current: index, of: count)
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .accessibilityIdentifier("expanded.pager")
    }

    /// A small vertical dot column showing which page is on screen.
    ///
    /// Without it a widget list of one and a widget list of many look the same until the user
    /// scrolls, and there is no cue that scrolling does anything.
    private func pageIndicator(current: Int, of count: Int) -> some View {
        VStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(.white.opacity(i == current ? 0.9 : 0.25))
                    .frame(width: 4, height: 4)
            }
        }
        .padding(.trailing, 4)
        .accessibilityIdentifier("expanded.pager.indicator")
    }

}
