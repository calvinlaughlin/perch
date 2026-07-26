import PerchCore
import SwiftUI

/// Owns the live widget instances and their lifecycle.
///
/// The lifecycle rule is the important part: a widget is activated only while it can actually be
/// seen, and deactivated the moment it cannot. A widget in the expanded panel does no work while
/// the notch is collapsed, and nothing does any work while the display is asleep. That is what
/// keeps perch at zero cost when it is just sitting on the bezel.
@MainActor
@Observable
public final class WidgetHost {

    private let registry: WidgetRegistry

    /// The widgets currently built, in config order.
    public private(set) var widgets: [any NotchWidget] = []

    /// Which widgets are currently doing work.
    private var active: Set<ObjectIdentifier> = []

    /// Whether the notch is visible at all.
    ///
    /// False while the display sleeps.
    private var isOnScreen = true

    /// What the notch is currently showing.
    private var state: NotchState = .collapsed

    private weak var attention: (any NotchAttention)?

    public init(registry: WidgetRegistry = .shared) {
        self.registry = registry
    }

    /// Rebuild every widget from a config.
    ///
    /// - Returns: diagnostics for widgets that could not be built.
    @discardableResult
    public func apply(config: Config) -> [Diagnostic] {
        // Tear the old ones down first. Rebuilding without this leaks whatever the previous
        // instances were holding, and config reloads happen on every save.
        deactivateAll()

        let (built, diagnostics) = registry.makeAll(for: config)
        widgets = built
        if let attention { for widget in widgets { widget.attach(attention: attention) } }
        syncActivation()
        return diagnostics
    }

    /// Give every widget a way to ask for attention.
    public func attach(attention: any NotchAttention) {
        self.attention = attention
        for widget in widgets { widget.attach(attention: attention) }
    }

    /// Note that the notch changed state, activating and deactivating as needed.
    public func notchStateChanged(to state: NotchState) {
        self.state = state
        syncActivation()
    }

    /// Note that the notch became visible or hidden entirely.
    public func setOnScreen(_ onScreen: Bool) {
        isOnScreen = onScreen
        syncActivation()
    }

    /// Stop everything.
    ///
    /// Called on quit.
    public func shutdown() {
        deactivateAll()
        widgets = []
    }

    /// The widgets drawn in a given position, in config order.
    public func widgets(at placement: Placement) -> [any NotchWidget] {
        widgets.filter { $0.placement == placement }
    }

    // MARK: - Lifecycle

    /// Whether a widget should currently be doing work.
    private func shouldRun(_ widget: any NotchWidget) -> Bool {
        // Nothing runs while the display is asleep, whatever it claims about its idle cost.
        guard isOnScreen else { return false }
        if widget.runsWhileHidden { return true }

        return switch widget.placement {
        case .leading, .trailing: true  // the collapsed strip is always on show
        case .expanded: state != .collapsed
        }
    }

    private func syncActivation() {
        for widget in widgets {
            let identifier = ObjectIdentifier(widget)
            let wants = shouldRun(widget)

            if wants, !active.contains(identifier) {
                widget.activate()
                active.insert(identifier)
            } else if !wants, active.contains(identifier) {
                widget.deactivate()
                active.remove(identifier)
            }
        }
    }

    private func deactivateAll() {
        for widget in widgets where active.contains(ObjectIdentifier(widget)) {
            widget.deactivate()
        }
        active.removeAll()
    }
}
