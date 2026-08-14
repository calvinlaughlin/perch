import Foundation
import PerchCore
import SwiftUI

/// Observable state backing the notch view.
///
/// Uses `@Observable` rather than `ObservableObject` so SwiftUI invalidates only the views that
/// actually read a changed property. With media metadata ticking on every playback update, blanket
/// `objectWillChange` invalidation would redraw the whole tree several times a second.
@MainActor
@Observable
public final class NotchModel {

    /// Resolved geometry for the display perch is currently on.
    public var layout: NotchLayout

    /// What the notch is currently showing.
    public var state: NotchState = .collapsed

    /// The config currently in effect.
    ///
    /// Held here so views read radii and debug flags straight from the schema rather than through
    /// a parallel set of view properties that could drift out of sync with it.
    public var config: Config

    /// Which expanded widget is currently shown, indexed into `WidgetHost.widgets(at: .expanded)`.
    ///
    /// The expanded panel shows one widget at a time and scrolls vertically between them, so this
    /// is what "the current page" means. Kept in-memory across close→reopen so the notch returns
    /// to whatever the user was last looking at rather than snapping back to the top every time.
    /// Bounds-checking lives at the read site — the widget list can shrink under a config reload.
    public var expandedPageIndex: Int = 0

    /// The kind of widget whose announcement the current peek belongs to, or `nil` when no peek is
    /// up.
    ///
    /// A peek is one widget saying one thing. Without this the panel drew every widget that had a
    /// `peekBody`, which was invisible while `media` was the only one that ever announced and
    /// wrong as soon as anything else did — a volume change would have shown you the current track.
    public var peekRequester: String?

    public init(layout: NotchLayout, config: Config = Config()) {
        self.layout = layout
        self.config = config
    }

    /// Whether the notch is showing more than the bare hardware shape.
    public var isOpen: Bool { state != .collapsed }

    /// The shape being drawn right now, in the panel's local coordinate space.
    ///
    public var activeRect: CGRect {
        switch state {
        case .collapsed: layout.collapsedRect
        case .peek: layout.peekRect
        case .expanded: layout.expandedRect
        }
    }

    /// Whether the notch is showing an announcement rather than a panel the user opened.
    public var isPeeking: Bool { state == .peek }

    /// Which widget belongs in `slot`.
    ///
    /// Slots run on forever in both directions and the widgets repeat under them, which is what
    /// makes the deck endless: nothing ever reaches an end and has to turn round. Scrolling down
    /// past the last card keeps going down, and the first card is simply what is next.
    ///
    /// Two `%` rather than one. Swift's remainder takes the sign of its left operand, so a negative
    /// slot — which is any slot above where the deck started, reachable by one scroll up — gives a
    /// negative index and traps on the way into the array.
    public nonisolated static func card(at slot: Int, of count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (slot % count + count) % count
    }

    /// One position in the endless run of slots, and which widget is printed on it.
    public struct Slot: Identifiable, Equatable, Sendable {

        /// Where this sits in the run.
        ///
        /// The run goes on forever in both directions, so this can be negative.
        public let offset: Int

        /// Index into the widget list.
        public let card: Int

        public var id: Int { offset }
    }

    /// The slots to build around `slot`: the one facing the reader and one either side.
    ///
    /// The neighbours are built so the card arriving is already laid out before it is needed —
    /// building only the current one leaves the space below it empty for the whole slide.
    ///
    /// Empty when there are no widgets, and that is the whole reason this exists rather than the
    /// call site mapping slots through `card(at:of:)` itself. A config can name only widgets that
    /// do not exist, which leaves nothing to deal; `card` answers 0 for an empty deck because it
    /// has no better answer to give, and 0 read out of an empty array takes the app down. There is
    /// no slot to fill here, so none is offered.
    public nonisolated static func window(around slot: Int, of count: Int) -> [Slot] {
        guard count > 0 else { return [] }
        return ((slot - 1)...(slot + 1)).map { Slot(offset: $0, card: card(at: $0, of: count)) }
    }
}
