import AppKit
import PerchCore
import SwiftUI

/// Owns the panel and keeps it aligned with the display underneath it.
///
/// Deliberately reuses a single `NotchPanel` for the lifetime of the app and *moves* it when the
/// display arrangement changes. Tearing down and recreating the window on every screen change is
/// the usual way notch apps end up with orphaned panels after a lid close or monitor unplug.
@MainActor
public final class NotchController {

    private let model: NotchModel
    private var options: NotchGeometryOptions

    private var panel: NotchPanel?
    private var hostingView: NotchHostingView<NotchRootView>?
    private var screenObservation: Task<Void, Never>?

    public init(options: NotchGeometryOptions = .default) {
        self.options = options
        // Resolve against the real display up front so the panel is never briefly misplaced.
        let geometry = NSScreen.preferredNotchScreen.map(ScreenGeometry.init(screen:))
        self.model = NotchModel(
            layout: NotchMetrics.resolve(
                for: geometry ?? Self.placeholderScreen,
                options: options
            )
        )
    }

    /// Show the notch and begin tracking display changes.
    public func start() {
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

    /// Tear everything down. Safe to call more than once.
    public func stop() {
        screenObservation?.cancel()
        screenObservation = nil
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

    /// Apply new geometry options — the path config reloads take.
    public func apply(options: NotchGeometryOptions) {
        self.options = options
        rebuild()
    }

    // MARK: - Panel lifecycle

    /// Re-resolve geometry for the current display and move the panel to match.
    private func rebuild() {
        guard let screen = NSScreen.preferredNotchScreen else {
            // Every display is gone (fully asleep, or a headless state). Hide rather than draw
            // into nothing, and wait for the next screen-parameters notification.
            panel?.orderOut(nil)
            return
        }

        let layout = NotchMetrics.resolve(for: ScreenGeometry(screen: screen), options: options)
        model.layout = layout

        let panel = existingPanel(sized: layout.panelRect)
        panel.setFrame(layout.panelRect, display: true)
        syncInteractiveRect()

        // `orderFrontRegardless` rather than `orderFront`: perch is an accessory app and is never
        // "active", so the ordinary ordering call would be a no-op.
        panel.orderFrontRegardless()
    }

    /// The panel, creating it on first use.
    private func existingPanel(sized frame: CGRect) -> NotchPanel {
        if let panel { return panel }

        let panel = NotchPanel(contentRect: frame)
        let hostingView = NotchHostingView(rootView: NotchRootView(model: model))

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
        panel.contentView = hostingView

        self.panel = panel
        self.hostingView = hostingView
        return panel
    }

    /// Keep the click-through region matched to the shape currently on screen.
    private func syncInteractiveRect() {
        hostingView?.interactiveRect = model.activeRect
    }

    /// Stand-in geometry for the window that would exist if no display were attached. Never drawn;
    /// it only keeps `NotchModel` non-optional so views don't need to handle a nil layout.
    private static let placeholderScreen = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        safeAreaTopInset: 0,
        auxiliaryTopLeftWidth: 0,
        auxiliaryTopRightWidth: 0,
        backingScaleFactor: 2
    )
}
