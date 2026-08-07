import PerchCore
import SwiftUI
import Testing

@testable import PerchUI

/// A widget that never overrides `peekBody`, standing in for every future widget.
@MainActor
private final class QuietWidget: NotchWidget {
    static let kind = "quiet"
    let placement = Placement.expanded
    init(settings: WidgetSettings) throws {}
    func activate() {}
    func deactivate() {}
    var body: AnyView { AnyView(Text("quiet")) }
}

/// Who gets to appear when the notch announces something.
///
/// A peek is the notch swelling unbidden. What it shows has to be what changed, and nothing else —
/// which is a rule about the *default*, since the widget nobody thought about is exactly the one
/// that ends up in there.
@MainActor
struct PeekContentTests {

    @Test("A widget that announces nothing has no peek")
    func quietWidgetsHaveNoPeek() throws {
        let widget = try QuietWidget(settings: WidgetSettings(kind: "quiet"))

        // Not "an empty view" — nothing at all, so the peek row can leave it out rather than
        // reserve space for it.
        #expect(widget.peekBody == nil)
    }

    @Test("Notes never appears in a peek")
    func notesHasNoPeek() throws {
        // The one this was written for: a track change announced a scratchpad, because the old
        // default handed every widget's full body to the peek.
        let notes = try NotesWidget(settings: WidgetSettings(kind: "notes"))

        #expect(notes.peekBody == nil)
    }

    @Test("The clock has nothing to announce either")
    func clockHasNoPeek() throws {
        // It changes every minute and announces none of them; a peek is for what *just* changed.
        let clock = try ClockWidget(settings: WidgetSettings(kind: "clock"))

        #expect(clock.peekBody == nil)
    }

    @Test("Media does have a peek, since it is what announces")
    func mediaHasAPeek() throws {
        let media = try MediaWidget(settings: WidgetSettings(kind: "media"))

        #expect(media.peekBody != nil)
    }

    @Test("A configured panel offers only the announcers to a peek")
    func onlyAnnouncersReachThePeek() {
        // What the peek row actually iterates. With both widgets configured, exactly one of them
        // has anything to say.
        let registry = WidgetRegistry()
        registry.register(MediaWidget.self)
        registry.register(NotesWidget.self)
        let host = WidgetHost(registry: registry)

        host.apply(config: ConfigLoader.load(source: "widget = media\nwidget = notes").config)

        #expect(host.widgets(at: .expanded).count == 2)
        #expect(host.widgets(at: .expanded).compactMap(\.peekBody).count == 1)
    }
}
