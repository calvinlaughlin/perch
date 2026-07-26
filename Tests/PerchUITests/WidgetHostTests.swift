import PerchCore
import SwiftUI
import Testing

@testable import PerchUI

/// A widget that records what the host did to it.
@MainActor
private final class SpyWidget: NotchWidget {
    static let kind = "spy"

    /// How many times work was started and stopped, so leaks and double-starts are both visible.
    private(set) var activations = 0
    private(set) var deactivations = 0
    var isRunning: Bool { activations > deactivations }

    let placement: Placement

    init(settings: WidgetSettings) throws {
        placement = try settings.enumeration("placement", default: .expanded)
    }

    func activate() { activations += 1 }
    func deactivate() { deactivations += 1 }
    var body: AnyView { AnyView(EmptyView()) }
}

/// A widget that refuses to be built, standing in for a bad setting.
@MainActor
private final class BrokenWidget: NotchWidget {
    static let kind = "broken"
    let placement = Placement.expanded
    init(settings: WidgetSettings) throws {
        throw ConfigValueError("broken-thing: this widget cannot be built")
    }
    func activate() {}
    func deactivate() {}
    var body: AnyView { AnyView(EmptyView()) }
}

extension WidgetHost {
    /// The spy instance, if one was built.
    ///
    /// `widgets.first as? SpyWidget` does not compile: `first` is an optional existential, and
    /// casting the optional itself always fails.
    @MainActor fileprivate var spy: SpyWidget? {
        widgets.compactMap { $0 as? SpyWidget }.first
    }
}

@MainActor
private func makeHost() -> (WidgetHost, WidgetRegistry) {
    let registry = WidgetRegistry()
    registry.register(SpyWidget.self)
    registry.register(BrokenWidget.self)
    return (WidgetHost(registry: registry), registry)
}

@MainActor
private func config(_ source: String) -> Config {
    // Clear the default widget list first: these tests are about the registry, and the real
    // default includes `media`, which the test registry deliberately does not know about.
    ConfigLoader.load(source: "widget =\n" + source).config
}

@Suite("Widget registry")
@MainActor
struct WidgetRegistryTests {
    @Test("A registered widget is built from config")
    func buildsRegisteredWidgets() {
        let (host, _) = makeHost()

        let diagnostics = host.apply(config: config("widget = spy"))

        #expect(host.widgets.count == 1)
        #expect(diagnostics.isEmpty)
    }

    @Test("An unknown widget is a diagnostic listing what exists")
    func unknownWidgetIsReported() {
        let (host, _) = makeHost()

        let diagnostics = host.apply(config: config("widget = wibble"))

        #expect(host.widgets.isEmpty)
        #expect(diagnostics.first?.message.contains("spy") == true)
    }

    @Test("One broken widget does not stop the others loading")
    func brokenWidgetDoesNotBlockOthers() {
        // Same rule as the rest of the config system: report and carry on.
        let (host, _) = makeHost()

        let diagnostics = host.apply(config: config("widget = broken\nwidget = spy"))

        #expect(host.widgets.count == 1)
        #expect(diagnostics.count == 1)
    }

    @Test("A widget reads its own settings")
    func widgetReadsItsSettings() {
        let (host, _) = makeHost()

        host.apply(config: config("widget = spy\nspy-placement = leading"))

        #expect(host.widgets.first?.placement == .leading)
    }
}

@Suite("Widget lifecycle")
@MainActor
struct WidgetLifecycleTests {
    @Test("A collapsed-strip widget runs as soon as it is built")
    func stripWidgetsRunImmediately() {
        let (host, _) = makeHost()

        host.apply(config: config("widget = spy\nspy-placement = leading"))

        let spy = host.spy
        #expect(spy?.isRunning == true)
    }

    @Test("An expanded widget does no work while the notch is collapsed")
    func expandedWidgetsIdleWhileCollapsed() {
        // The whole zero-idle-cost claim rests on this.
        let (host, _) = makeHost()

        host.apply(config: config("widget = spy\nspy-placement = expanded"))

        let spy = host.spy
        #expect(spy?.isRunning == false)
    }

    @Test("Opening the notch starts expanded widgets, closing it stops them")
    func expandedWidgetsFollowTheNotch() {
        let (host, _) = makeHost()
        host.apply(config: config("widget = spy"))
        let spy = host.spy

        host.notchStateChanged(to: .expanded)
        #expect(spy?.isRunning == true)

        host.notchStateChanged(to: .collapsed)
        #expect(spy?.isRunning == false)
    }

    @Test("Repeated state changes do not restart a running widget")
    func doesNotRestartRunningWidgets() {
        let (host, _) = makeHost()
        host.apply(config: config("widget = spy"))
        let spy = host.spy

        host.notchStateChanged(to: .expanded)
        host.notchStateChanged(to: .peek)
        host.notchStateChanged(to: .expanded)

        #expect(spy?.activations == 1)
    }

    @Test("Leaving the screen stops every widget")
    func leavingTheScreenStopsEverything() {
        let (host, _) = makeHost()
        host.apply(config: config("widget = spy\nspy-placement = leading"))
        let spy = host.spy

        host.setOnScreen(false)

        #expect(spy?.isRunning == false)
    }

    @Test("Reloading config stops the old widgets before building new ones")
    func reloadStopsOldWidgets() {
        // Config reloads happen on every save; leaking an instance each time would add up fast.
        let (host, _) = makeHost()
        host.apply(config: config("widget = spy\nspy-placement = leading"))
        let original = host.spy

        host.apply(config: config("widget = spy\nspy-placement = leading"))

        #expect(original?.isRunning == false)
        #expect(original !== host.spy)
    }

    @Test("Shutdown stops everything and drops the widgets")
    func shutdownStopsEverything() {
        let (host, _) = makeHost()
        host.apply(config: config("widget = spy\nspy-placement = leading"))
        let spy = host.spy

        host.shutdown()

        #expect(spy?.isRunning == false)
        #expect(host.widgets.isEmpty)
    }

    @Test("Widgets are grouped by placement in config order")
    func groupsByPlacement() {
        let (host, _) = makeHost()
        host.apply(config: config("widget = spy\nspy-placement = trailing"))

        #expect(host.widgets(at: .trailing).count == 1)
        #expect(host.widgets(at: .expanded).isEmpty)
    }
}
