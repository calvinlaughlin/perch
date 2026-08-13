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
    /// One widget faces the reader at a time and scrolling vertically moves between them, one per
    /// gesture. The choice is remembered on `model.expandedPageIndex`, so a close-and-reopen
    /// returns to the same card rather than snapping back to the first.
    ///
    /// That is the deliberate compromise for a panel this small: two widgets crammed side-by-side
    /// each get less than half the width, but one at a time gets the full row.
    private var expandedContent: some View {
        let rect = model.layout.expandedRect
        let housingHeight = model.layout.hardwareRect.height
        let inset = PanelMetrics.panelInset
        let widgets = host.widgets(at: .expanded)

        return ExpandedDeck(model: model, widgets: widgets)
            .frame(
                width: max(0, rect.width - inset * 2),
                // Start below the housing: content drawn behind it is content nobody can see.
                // Inset at the bottom too, so a widget does not have to pad itself to look
                // centred — the box it is handed is already symmetric.
                height: max(0, rect.height - housingHeight - inset * 2)
            )
            .position(
                x: rect.midX,
                y: housingHeight + (rect.height - housingHeight) / 2
            )
    }

    /// Widgets in a peek: compact, centred, no controls.
    ///
    /// Only widgets with something to announce appear. A peek belongs to whatever just changed —
    /// everything else configured into the panel is beside the point for the two seconds it is up,
    /// and a scratchpad arriving because a track changed is not an announcement of anything.
    private var peekContent: some View {
        let rect = model.layout.peekRect
        let housingHeight = model.layout.hardwareRect.height
        let inset = PanelMetrics.panelInset

        return HStack(spacing: PanelMetrics.columnGap) {
            ForEach(Array(host.announcementWidgets.enumerated()), id: \.offset) { _, widget in
                widget.peekBody
            }
        }
        .frame(
            width: max(0, rect.width - inset * 2),
            height: max(0, rect.height - housingHeight - inset * 2)
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
    ///
    /// One unit, and an optical correction rather than a spacing value: the shape's bottom corners
    /// are rounded, so a row centred by measurement sits closer to the edge than it looks.
    private let peekBottomBias = PanelMetrics.unit

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
        HStack(spacing: PanelMetrics.rowGap) {
            ForEach(Array(widgets.enumerated()), id: \.offset) { _, widget in
                widget.body
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .padding(.horizontal, PanelMetrics.rowGap)
    }
}

// MARK: - Expanded deck

/// Shows the expanded widgets as an endless deck of cards sliding vertically.
///
/// Endless in the real sense: there is no last card to reach. `expandedPageIndex` is a position on
/// a run of slots that goes on forever in both directions, and the widgets simply repeat underneath
/// it — so scrolling down past the final widget carries on downwards into the first, rather than
/// sweeping back up to the top. Nothing ever turns round, so nothing ever has to be told which way
/// to turn.
///
/// Only the slots either side of the current one are built, and each is keyed by its slot number.
/// That identity is the load-bearing part. Keyed by slot, a card that scrolls out of the window is
/// removed and a new one inserted at the far end, both off screen; keyed by widget instead, SwiftUI
/// would see the same view move from one end of the deck to the other and animate it travelling
/// right across the panel to get there.
///
/// Nothing is rotated or rasterised on the way, so text stays crisp for the whole slide. That was
/// the failing of the spindle this replaced — a card mid-turn is a texture, and a texture of text is
/// a smear.
private struct ExpandedDeck: View {

    @Bindable var model: NotchModel
    let widgets: [any NotchWidget]

    /// The gap between cards, so the one arriving is not mistaken for more of the one leaving.
    private let gap = PanelMetrics.cardGap

    var body: some View {
        // Read out here, not inside the `GeometryReader`. Observation is established while the body
        // is evaluated, and a `GeometryReader`'s closure runs later, during layout — state read only
        // in there can fail to register as a dependency, which shows up as the index changing
        // correctly while nothing on screen ever moves.
        let index = model.expandedPageIndex

        return GeometryReader { proxy in
            let face = proxy.size.height
            let step = face + gap

            ZStack(alignment: .top) {
                // The window hands back the slot facing the reader and one either side, so the card
                // arriving is already built and laid out before it is needed — and hands back
                // nothing at all when there are no widgets, rather than a slot with no card on it.
                ForEach(NotchModel.window(around: index, of: widgets.count)) { slot in
                    widgets[slot.card].body
                        // Every card is the same face, whatever is printed on it. Without this each
                        // widget takes its own intrinsic height and the deck stops being a deck —
                        // the slide would travel a different distance per card.
                        .frame(width: proxy.size.width, height: face)
                        .clipped()
                        .offset(y: CGFloat(slot.offset) * step)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            // The whole run of slots shifts under the panel. Slot positions are absolute and never
            // change, so this single offset is the only thing that animates — which is why the
            // movement is continuous rather than a set of cards each deciding where to go.
            .offset(y: -CGFloat(index) * step)
        }
        .clipped()
        .contentShape(Rectangle())
        .accessibilityIdentifier("expanded.deck")
    }
}
