import AppKit
import PerchCore
import SwiftUI

/// Owns the panel, the interaction state machine, and the current config.
///
/// Deliberately reuses a single `NotchPanel` for the lifetime of the app and *moves* it when the
/// display arrangement changes. Tearing down and recreating the window on every screen change is
/// the usual way notch apps end up with orphaned panels after a lid close or monitor unplug.
@MainActor
public final class NotchController: NotchAttention {

    private let model: NotchModel
    private let host: WidgetHost
    private var config: Config
    private var machine: NotchStateMachine

    private var panel: NotchPanel?
    private var hostingView: NotchHostingView<NotchRootView>?
    private var screenObservation: Task<Void, Never>?
    private var hoverSettleTask: Task<Void, Never>?
    private var peekExpiryTask: Task<Void, Never>?

    public init(config: Config = Config(), host: WidgetHost = WidgetHost()) {
        self.config = config
        self.host = host
        self.machine = NotchStateMachine(openTrigger: config.openOn)

        // Resolve against the real display up front so the panel is never briefly misplaced.
        let geometry = NSScreen.preferredScreen(matching: config.display)
            .map(ScreenGeometry.init(screen:))
        self.model = NotchModel(
            layout: NotchMetrics.resolve(
                for: geometry ?? Self.placeholderScreen,
                options: config.geometryOptions
            ),
            config: config
        )
    }

    /// Diagnostics from the most recent widget build, for the caller to report.
    public private(set) var widgetDiagnostics: [Diagnostic] = []

    /// Called when the user asks for a config reload from the notch menu.
    public var onReloadRequested: (() -> Void)?

    /// Show the notch and begin tracking display changes.
    public func start() {
        widgetDiagnostics = host.apply(config: config)
        host.attach(attention: self)
        host.notchStateChanged(to: machine.state)
        rebuild()

        // Fires on resolution changes, display connect/disconnect, lid open/close, and menu bar
        // visibility changes — every event that can invalidate our geometry.
        screenObservation = Task { [weak self] in
            let changes = NotificationCenter.default.notifications(
                named: NSApplication.didChangeScreenParametersNotification
            )
            for await _ in changes {
                guard let self else { return }
                self.rebuild()
            }
        }
    }

    /// Tear everything down.
    ///
    /// Safe to call more than once.
    public func stop() {
        screenObservation?.cancel()
        screenObservation = nil
        hoverSettleTask?.cancel()
        hoverSettleTask = nil
        host.shutdown()
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

    /// Adopt a new config — the path a config-file reload takes.
    public func apply(config: Config) {
        // A reload fires for every save, including saves that changed a comment or nothing at all,
        // and `ConfigWatcher.start()` delivers the same config the app launched with. Rebuilding
        // the panel for those is wasted work the user can sometimes see.
        guard config != self.config else { return }

        self.config = config
        machine.openTrigger = config.openOn
        model.config = config
        widgetDiagnostics = host.apply(config: config)
        host.attach(attention: self)
        host.notchStateChanged(to: machine.state)
        rebuild()
    }

    // MARK: - Interaction

    private func pointerEntered() {
        deliver(.pointerEntered)

        // `open-delay` keeps the notch shut while the pointer is merely passing through on its way
        // to the menu bar. Cancelled the moment the pointer leaves, so a fly-by never opens it.
        hoverSettleTask?.cancel()
        guard config.openOn == .hover else { return }

        let delay = config.openDelay
        guard delay > .zero else {
            deliver(.hoverSettled)
            return
        }

        hoverSettleTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.deliver(.hoverSettled)
        }
    }

    private func pointerExited() {
        hoverSettleTask?.cancel()
        hoverSettleTask = nil
        deliver(.pointerExited)
    }

    /// A widget asked for attention.
    ///
    /// Timing lives here rather than in the state machine, which stays pure and synchronous so
    /// every transition can be tested without waiting on a clock.
    public func requestPeek() {
        guard config.peekOnTrackChange else { return }

        deliver(.peekRequested)
        peekExpiryTask?.cancel()

        let duration = config.peekDuration
        peekExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.deliver(.peekExpired)
        }
    }

    private func clicked() {
        hoverSettleTask?.cancel()
        hoverSettleTask = nil
        deliver(.clicked)
    }

    /// Push an event through the state machine and reflect any change in the view.
    private func deliver(_ event: NotchEvent) {
        guard machine.handle(event) else { return }
        model.state = machine.state
        host.notchStateChanged(to: machine.state)
        syncInteractiveRect()
    }

    // MARK: - Panel lifecycle

    /// Re-resolve geometry for the current display and move the panel to match.
    private func rebuild() {
        guard let screen = NSScreen.preferredScreen(matching: config.display) else {
            // Every display is gone (fully asleep, or a headless state). Hide rather than draw
            // into nothing, and wait for the next screen-parameters notification.
            host.setOnScreen(false)
            panel?.orderOut(nil)
            return
        }

        host.setOnScreen(true)

        let layout = NotchMetrics.resolve(
            for: ScreenGeometry(screen: screen),
            options: config.geometryOptions
        )
        model.layout = layout

        let panel = existingPanel(sized: layout.panelRect)
        panel.setFrame(layout.panelRect, display: true)
        syncInteractiveRect()

        // `orderFrontRegardless` rather than `orderFront`: perch is an accessory app and is never
        // "active", so the ordinary ordering call would be a no-op.
        panel.orderFrontRegardless()

        Log.geometry.info(
            """
            \(layout.kind == .hardware ? "hardware notch" : "synthetic pill") on \
            \(screen.localizedName) — panel \(Self.describe(layout.panelRect)), \
            collapsed \(Self.describe(layout.collapsedRect))
            """
        )
    }

    /// The panel, creating it on first use.
    private func existingPanel(sized frame: CGRect) -> NotchPanel {
        if let panel { return panel }

        let panel = NotchPanel(contentRect: frame)
        let hostingView = NotchHostingView(rootView: NotchRootView(model: model, host: host))

        // Opt out of safe-area insets entirely. On a notched display AppKit would otherwise inset
        // this view by the notch height — pushing our content *below* the exact region we exist to
        // draw in. `.ignoresSafeArea()` inside the SwiftUI tree is not enough; the inset is applied
        // by the hosting view itself, above where that modifier can reach.
        hostingView.safeAreaRegions = []

        // Stop SwiftUI's ideal size from propagating back into the window. Without this the
        // hosting view resizes the panel to fit its content, so the window silently grows by the
        // shape's shoulder overhang and our carefully computed frame stops matching the hardware.
        // The panel's size is decided by NotchMetrics, full stop.
        hostingView.sizingOptions = []

        hostingView.frame = CGRect(origin: .zero, size: frame.size)
        hostingView.autoresizingMask = [.width, .height]

        hostingView.onPointerEntered = { [weak self] in self?.pointerEntered() }
        hostingView.onPointerExited = { [weak self] in self?.pointerExited() }
        hostingView.onClick = { [weak self] in self?.clicked() }
        let _unused: () -> Void = {}; _ = _unused;
        let _skip = { [weak self] in
            NotchMenu.make(
                reload: { self?.onReloadRequested?() },
                quit: { NSApp.terminate(nil) }
            )
        }; _ = _skip

        panel.contentView = hostingView

        self.panel = panel
        self.hostingView = hostingView
        return panel
    }

    /// Format a rect compactly for logging.
    private static func describe(_ rect: CGRect) -> String {
        "\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))×\(Int(rect.height))"
    }

    /// Keep the click-through and toggle regions matched to the shape currently on screen.
    private func syncInteractiveRect() {
        hostingView?.interactiveRect = model.activeRect

        // Collapsed, the whole shape toggles — there is nothing else to click. Open, only the band
        // across the top does, so it acts as a title bar and the widgets below get their clicks.
        hostingView?.toggleRect =
            model.isOpen
            ? CGRect(
                x: model.activeRect.minX, y: 0,
                width: model.activeRect.width, height: model.layout.hardwareRect.height)
            : model.activeRect
    }

    /// Stand-in geometry for the window that would exist if no display were attached.
    ///
    /// Never drawn; it only keeps `NotchModel` non-optional so views don't need to handle a nil
    /// layout.
    private static let placeholderScreen = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        safeAreaTopInset: 0,
        auxiliaryTopLeftWidth: 0,
        auxiliaryTopRightWidth: 0,
        backingScaleFactor: 2
    )
}
