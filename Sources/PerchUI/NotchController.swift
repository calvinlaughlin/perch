import AppKit
import PerchCore
import SwiftUI

/// Owns the panel, the interaction state machine, and the current config.
///
/// Deliberately reuses a single `NotchPanel` for the lifetime of the app and *moves* it when the
/// display arrangement changes. Tearing down and recreating the window on every screen change is
/// the usual way notch apps end up with orphaned panels after a lid close or monitor unplug.
@MainActor
public final class NotchController: AttributedAttention {

    private let model: NotchModel
    private let host: WidgetHost
    private let haptics: HapticEngine
    private var config: Config
    private var machine: NotchStateMachine

    private var panel: NotchPanel?
    private var hostingView: NotchHostingView<NotchRootView>?
    private var screenObservation: Task<Void, Never>?
    private var hoverSettleTask: Task<Void, Never>?
    private var peekExpiryTask: Task<Void, Never>?
    private var scrollMonitor: Any?

    /// Decides when a stream of scroll events amounts to turning a card.
    private var pager = ScrollPager()

    public init(
        config: Config = Config(),
        host: WidgetHost = WidgetHost(),
        haptics: HapticEngine = .system
    ) {
        self.config = config
        self.host = host
        self.haptics = haptics
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

        installScrollMonitor()
    }

    /// Watch every scroll event the app sees and route the ones landing on the notch to the pager.
    ///
    /// A local monitor rather than a `scrollWheel` override on the hosting view because SwiftUI
    /// widgets can contain their own scroll views — `TextEditor` is one — and those swallow the
    /// wheel event before it ever reaches our container. The monitor sees the event first, decides
    /// whether it is destined for us, and returns nil to consume it so the inner scroll view never
    /// gets a look.
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
            [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }
            guard self.model.state == .expanded else { return event }

            // The event's location is in window coordinates with y-up. Convert to the SwiftUI
            // layout space the interactive rect is expressed in, exactly the way NotchHostingView
            // does for its own hit tests.
            let location = event.locationInWindow
            let inRect = self.model.activeRect.contains(
                CGPoint(x: location.x, y: panel.frame.height - location.y)
            )
            guard inRect else { return event }

            let phase = Self.phase(of: event)

            // The start and end of a gesture carry no movement at all, so they cannot be filtered
            // by which way they point — and they are exactly the ones the pager needs, because
            // `.ended` is what releases its one-card-per-gesture latch. Judge those on being
            // boundaries; judge everything else on its axis.
            //
            // Getting this wrong does not look like a filtering bug. The latch is set by the first
            // swipe and then never released, so precisely one card change works and the deck is
            // dead from then on.
            let isBoundary = phase == .began || phase == .ended

            // Vertical scrolling moves the cards, and the deck slides vertically to match. A
            // horizontal swipe is left alone and passed on, so a sideways gesture that happens to
            // cross the notch on its way somewhere else is not swallowed by it.
            let isVertical = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)

            guard isVertical || isBoundary else { return event }

            self.scrolled(delta: event.scrollingDeltaY, phase: phase)

            // Consume only what was actually used.
            return isVertical ? nil : event
        }
    }

    /// Which part of a gesture an AppKit scroll event belongs to.
    ///
    /// AppKit splits this across two separate masks, and the order of the checks is what makes the
    /// distinction usable. `momentumPhase` is tested first because an event coasting after the
    /// fingers left still carries a `phase` of `.changed` — read the wrong one first and the coast
    /// is indistinguishable from the gesture, which is precisely how one flick turns the whole
    /// wheel. An event with neither mask set is a wheel mouse, which has no gesture at all.
    private static func phase(of event: NSEvent) -> ScrollPager.Phase {
        if !event.momentumPhase.isEmpty { return .momentum }
        if event.phase.contains(.began) { return .began }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) { return .ended }
        if event.phase.contains(.changed) { return .changed }
        return .discrete
    }

    /// Tear everything down.
    ///
    /// Safe to call more than once.
    public func stop() {
        screenObservation?.cancel()
        screenObservation = nil
        hoverSettleTask?.cancel()
        hoverSettleTask = nil
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
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
    public func requestPeek(from kind: String) {
        guard announcementsAllowed(for: kind) else { return }

        model.peekRequester = kind
        deliver(.peekRequested)
        peekExpiryTask?.cancel()

        let duration = config.peekDuration
        peekExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.model.peekRequester = nil
            self?.deliver(.peekExpired)
        }
    }

    /// Whether this widget is permitted to announce.
    ///
    /// `peek-on-track-change` is a core key that only ever meant something to `media` — it predates
    /// there being a second widget with anything to announce. Gating *every* peek on it would mean
    /// someone who turned off track announcements silently got no volume HUD either, which is not
    /// what that line says. Scoped to media until the key can be moved into the media namespace,
    /// which cannot happen without breaking existing config files.
    private func announcementsAllowed(for kind: String) -> Bool {
        kind == "media" ? config.peekOnTrackChange : true
    }

    private func clicked() {
        hoverSettleTask?.cancel()
        hoverSettleTask = nil
        deliver(.clicked)
    }

    /// A scroll event landed on the notch.
    ///
    /// Only meaningful while the panel is open: collapsed there is nothing to turn between, and a
    /// peek is an announcement rather than an interaction. Whether a given event actually turns a
    /// card is `ScrollPager`'s decision, which is where the awkward part lives and where it can be
    /// tested; this only carries the answer out to the model, the animation, and the trackpad.
    private func scrolled(delta: CGFloat, phase: ScrollPager.Phase) {
        guard model.state == .expanded else { return }

        let widgets = host.widgets(at: .expanded)
        guard widgets.count > 1 else { return }

        let step = pager.scrolled(delta: delta, phase: phase)
        guard step != 0 else { return }

        // The only difference between the two behaviours, and the reason this is one key rather
        // than two implementations. Endless leaves the index running free on a slot line that never
        // ends; rewind folds it back into the widget list, which the deck then reaches by sliding
        // across everything in between. The view draws both without knowing which it is showing.
        let next =
            switch config.expandedScroll {
            case .endless:
                model.expandedPageIndex + step
            case .rewind:
                NotchModel.card(
                    at: model.expandedPageIndex + step, of: widgets.count)
            }
        guard next != model.expandedPageIndex else { return }

        // Tapped as the turn begins rather than when the animation settles. The tap is meant to
        // land with the finger that caused it — a detent felt a third of a second late reads as a
        // second, unexplained event rather than as the card reaching its stop.
        haptics.performCardTurn(config.hapticPolicy)

        // A short spring with a little give, so the deck arrives with some weight rather than
        // stopping dead. Nothing here is rasterised or rotated, so unlike the turn this replaced,
        // the movement can afford to be watched.
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            model.expandedPageIndex = next
        }
    }

    /// Push an event through the state machine and reflect any change in the view.
    private func deliver(_ event: NotchEvent) {
        let previous = machine.state
        guard machine.handle(event) else { return }
        model.state = machine.state

        // Only on a real transition, which is what `handle` returning true means. Hover sends
        // `pointerEntered` and `hoverSettled` for one opening, and a notch already open keeps
        // receiving events — tapping for each would turn one gesture into a stutter.
        haptics.perform(config.hapticPolicy, from: previous, to: machine.state)

        host.notchStateChanged(to: machine.state)
        syncInteractiveRect()
        syncKeyStatus()
    }

    /// Match the panel's willingness to accept keyboard input to whether it is actually open.
    ///
    /// Expanded is the only state where a widget can plausibly want typing — the collapsed strip
    /// has no text field, and a peek is announcing something you did not ask to see. Making the
    /// panel key any earlier would steal focus from the user's real work, which is exactly what
    /// `.nonactivatingPanel` was chosen to prevent.
    private func syncKeyStatus() {
        guard let panel else { return }
        if machine.state == .expanded {
            panel.focusable = true
            panel.makeKey()
        } else if panel.isKeyWindow {
            panel.focusable = false
            panel.resignKey()
        } else {
            panel.focusable = false
        }
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
        hostingView.makeMenu = { [weak self] in
            NotchMenu.make(
                reload: { self?.onReloadRequested?() },
                quit: { NSApp.terminate(nil) }
            )
        }

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
