import PerchCore
import SwiftUI
import Testing

@testable import PerchUI

/// A widget that always has something to announce, like `media`.
@MainActor
private final class LoudWidget: NotchWidget {
    static let kind = "loud"
    let placement: Placement = .expanded

    init(settings: WidgetSettings) throws {}

    func activate() {}
    func deactivate() {}

    var body: AnyView { AnyView(EmptyView()) }
    var peekBody: AnyView? { AnyView(Text("loud")) }

    /// Kept so a test can make it ask for attention the way a real widget does.
    private(set) var attention: (any NotchAttention)?
    func attach(attention: any NotchAttention) { self.attention = attention }
}

/// A second announcing widget — the thing that never existed before the HUD.
@MainActor
private final class OtherLoudWidget: NotchWidget {
    static let kind = "other"
    let placement: Placement = .expanded

    init(settings: WidgetSettings) throws {}

    func activate() {}
    func deactivate() {}

    var body: AnyView { AnyView(EmptyView()) }
    var peekBody: AnyView? { AnyView(Text("other")) }

    private(set) var attention: (any NotchAttention)?
    func attach(attention: any NotchAttention) { self.attention = attention }
}

/// Records who asked, standing in for the controller.
@MainActor
private final class SpyAttention: AttributedAttention {
    private(set) var requests: [String] = []
    func requestPeek(from kind: String) { requests.append(kind) }
}

@Suite("Peek attribution")
@MainActor
struct PeekAttributionTests {

    private func makeHost() -> (WidgetHost, SpyAttention) {
        let registry = WidgetRegistry()
        registry.register(LoudWidget.self)
        registry.register(OtherLoudWidget.self)

        let host = WidgetHost(registry: registry)
        var config = Config()
        config.widgets = ["loud", "other"]
        host.apply(config: config)

        let attention = SpyAttention()
        host.attach(attention: attention)
        return (host, attention)
    }

    @Test("A widget's peek request arrives carrying its own kind")
    func requestsAreTagged() {
        // Widgets never say who they are — the host wraps each one so it cannot name someone else
        // and cannot forget to name itself.
        let (host, attention) = makeHost()

        let loud = host.widgets(at: .expanded).compactMap { $0 as? LoudWidget }.first
        let other = host.widgets(at: .expanded).compactMap { $0 as? OtherLoudWidget }.first

        loud?.attention?.requestPeek()
        other?.attention?.requestPeek()

        #expect(attention.requests == ["loud", "other"])
    }

    @Test("A peek shows only the widget that asked for it")
    func peekShowsOnlyTheRequester() {
        // The whole reason a second announcing widget was impossible before. Both of these have a
        // non-nil peekBody at all times, exactly like MediaWidget does.
        let (host, _) = makeHost()

        let announcers = host.announcers(for: "loud")

        #expect(announcers.count == 1)
        #expect(announcers.first?.kind == "loud")
    }

    @Test("The other announcing widget is not dragged along")
    func theOtherWidgetIsExcluded() {
        let (host, _) = makeHost()

        #expect(host.announcers(for: "other").map(\.kind) == ["other"])
    }

    @Test("No peek means nothing is announced")
    func noRequesterShowsNothing() {
        // The collapsed and user-opened states both leave this nil, and a panel the user opened
        // deliberately must never turn into somebody's announcement.
        let (host, _) = makeHost()

        #expect(host.announcers(for: nil).isEmpty)
    }

    @Test("A widget with nothing to say contributes nothing even when it asked")
    func silentRequesterShowsNothing() {
        // HudWidget's peekBody is nil unless an announcement is live, so a stale requester left
        // over from an expired peek cannot resurrect its content.
        let registry = WidgetRegistry()
        registry.register(QuietWidget.self)

        let host = WidgetHost(registry: registry)
        var config = Config()
        config.widgets = ["quiet"]
        host.apply(config: config)

        #expect(host.announcers(for: "quiet").isEmpty)
    }
}

/// Announces nothing, like `clock` and `notes`.
@MainActor
private final class QuietWidget: NotchWidget {
    static let kind = "quiet"
    let placement: Placement = .expanded

    init(settings: WidgetSettings) throws {}

    func activate() {}
    func deactivate() {}

    var body: AnyView { AnyView(EmptyView()) }
}
