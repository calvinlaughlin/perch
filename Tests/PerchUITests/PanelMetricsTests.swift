import CoreGraphics
import PerchCore
import Testing

@testable import PerchUI

/// The panel's arithmetic.
///
/// A layout whose pieces are chosen one at a time stops summing to anything in particular, and the
/// symptom is not a compile error — it is a panel that clips its own last row, or a default height
/// nudged upward until things look right. These are the sums, written down.
@MainActor
struct PanelMetricsTests {

    @Test("Every spacing value is a whole number of units")
    func everythingIsOnTheScale() {
        let values: [(String, CGFloat)] = [
            ("panelInset", PanelMetrics.panelInset),
            ("rowGap", PanelMetrics.rowGap),
            ("columnGap", PanelMetrics.columnGap),
            ("textGap", PanelMetrics.textGap),
            ("cardGap", PanelMetrics.cardGap),
            ("control", PanelMetrics.control),
            ("controlGap", PanelMetrics.controlGap),
            ("scrubberRow", PanelMetrics.scrubberRow),
            ("bar", PanelMetrics.bar),
            ("artwork", PanelMetrics.artwork),
            ("peekArtwork", PanelMetrics.peekArtwork),
            ("artworkRadius", PanelMetrics.artworkRadius),
        ]

        for (name, value) in values {
            let units = value / PanelMetrics.unit
            #expect(units == units.rounded(), "\(name) is \(value), not a multiple of the unit")
        }
    }

    @Test("The media widget fits its panel exactly")
    func mediaFitsExactly() {
        // Exactly, not merely within. Slack means the numbers were picked to look right rather
        // than to be right, and it is where the next arbitrary value hides.
        let available = PanelMetrics.contentHeight(panelHeight: Config().expandedHeight)

        #expect(PanelMetrics.mediaHeight() == available)
    }

    @Test("The shipped default is the height the layout asks for")
    func defaultHeightMatchesTheLayout() {
        // `Config` lives in PerchCore, which cannot see PerchUI, so the default is a literal there
        // and this is the only thing holding the two together. Change either and this fails.
        #expect(Config().expandedHeight == PanelMetrics.expandedHeightForMedia)
    }

    @Test("The band is as tall as the artwork, not as its neighbours")
    func artworkSetsTheBandHeight() {
        // The row's height is the artwork's, so the text and the controls beside it must both fit
        // inside that. If a control ever grew past it, the band would silently get taller and the
        // scrubber would be pushed out of the panel.
        #expect(PanelMetrics.control < PanelMetrics.artwork)
    }

    @Test("A peek's artwork fits a peek")
    func peekArtworkFitsThePeek() {
        let available = PanelMetrics.contentHeight(panelHeight: Config().peekHeight)

        #expect(PanelMetrics.peekArtwork <= available)
    }

    @Test("The transport row is its buttons and the gaps between them")
    func controlsAddUp() {
        #expect(PanelMetrics.controls == PanelMetrics.control * 3 + PanelMetrics.controlGap * 2)
        // It has to leave the text something to live in, on the narrowest panel anyone would set.
        let narrow: CGFloat = 320
        let text =
            narrow - PanelMetrics.panelInset * 2 - PanelMetrics.artwork
            - PanelMetrics.columnGap * 2 - PanelMetrics.controls
        #expect(text > 0, "no room for a title at \(narrow)pt wide")
    }
}
