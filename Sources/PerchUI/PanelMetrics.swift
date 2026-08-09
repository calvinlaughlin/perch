import CoreGraphics

/// The spacing scale everything in the panel is built from.
///
/// One number, `unit`, and every gap, inset, and control size is a whole multiple of it. Not for
/// its own sake: a panel this small has room for one row of content, so its height is the sum of a
/// handful of values, and when those values are picked one at a time the sum stops being anything
/// in particular. `expanded-height` then gets nudged until it looks right, which is how a layout
/// ends up with a 5pt pad at the bottom compensating for a 10pt inset at the top.
///
/// The budget below adds up exactly. If a change makes it stop adding up, `PanelMetricsTests`
/// fails rather than the panel quietly clipping its own last row.
///
/// Named `PanelMetrics` rather than the obvious `Layout` because SwiftUI declares a `Layout`
/// protocol, and every file here imports SwiftUI — the same collision `NotchWidget` avoids with
/// `Widget`. `NotchLayout` was taken too: that is the geometry of the shape, in `PerchCore`, and
/// this is the spacing of what is drawn inside it.
public enum PanelMetrics {

    /// The scale.
    ///
    /// Everything else is a whole multiple of this.
    public static let unit: CGFloat = 4

    // MARK: - The panel

    /// Margin between the panel's edges and its content, on all four sides.
    ///
    /// All four deliberately. It used to be applied to the sides and the top only, leaving content
    /// flush with the bottom edge — which reads as the panel being bottom-heavy, and invites each
    /// widget to invent its own bottom padding to fix it.
    public static let panelInset = unit * 3  // 12

    /// Between stacked rows inside a widget.
    public static let rowGap = unit * 3  // 12

    /// Between things side by side: artwork, text, controls.
    public static let columnGap = unit * 3  // 12

    /// Between a title and the line under it.
    ///
    /// Type rather than layout, and tight on purpose.
    public static let textGap = unit  // 4

    /// Between cards in the deck, so the one arriving is not read as more of the one leaving.
    public static let cardGap = unit * 3  // 12

    // MARK: - Controls

    /// A transport button's hit area, which is deliberately larger than its glyph.
    public static let control = unit * 8  // 32

    /// Between transport buttons, so the one in the middle is the one under the pointer.
    public static let controlGap = unit * 4  // 16

    /// The full transport row: three buttons and the two gaps between them.
    public static let controls = control * 3 + controlGap * 2  // 128

    // MARK: - The scrubber

    /// The scrubber's row, times included.
    public static let scrubberRow = unit * 4  // 16

    /// The drawn bar.
    ///
    /// The row around it is taller, so the gesture has something to hit.
    public static let bar = unit  // 4

    // MARK: - Artwork

    /// Album art in the open panel.
    ///
    /// The tallest thing in the band, so it is what sets the row's height.
    public static let artwork = unit * 12  // 48

    /// Album art in a peek, which is shorter than the panel and carries no controls.
    public static let peekArtwork = unit * 8  // 32

    /// Rounded corners on artwork.
    public static let artworkRadius = unit * 2  // 8

    // MARK: - The budget

    /// Content height available inside a panel of a given height.
    public static func contentHeight(panelHeight: CGFloat) -> CGFloat {
        panelHeight - panelInset * 2
    }

    /// What the media widget needs vertically: the band, then the scrubber under it.
    ///
    /// The band is as tall as the artwork, which is taller than either the two lines of text or the
    /// transport buttons beside it — so artwork alone decides it.
    public static func mediaHeight(artwork: CGFloat = PanelMetrics.artwork) -> CGFloat {
        artwork + rowGap + scrubberRow
    }

    /// The smallest `expanded-height` that fits the media widget without clipping it.
    ///
    /// `Config.expandedHeight` defaults to exactly this. Lower it in a config file and the scrubber
    /// is what runs out of room first, which is a choice available to anyone who wants a shorter
    /// panel more than they want the bar.
    public static let expandedHeightForMedia = mediaHeight() + panelInset * 2  // 100
}
