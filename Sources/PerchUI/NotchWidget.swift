import PerchCore
import SwiftUI

/// Something perch draws in the notch.
///
/// Named `NotchWidget` rather than the obvious `Widget` because SwiftUI already declares a
/// `Widget` protocol for WidgetKit extensions. Any file importing both SwiftUI and PerchUI would
/// otherwise fail with "'Widget' is ambiguous for type lookup" — and since every widget file
/// imports SwiftUI, that means every widget file.
///
/// The protocol lives here rather than in `PerchCore` because of `body`: widgets are SwiftUI, and
/// `PerchCore` is deliberately free of UI frameworks so geometry, config, and state stay testable
/// without a display. The configuration half — `WidgetSettings`, `Placement` — is in core, and this
/// is the rendering half.
///
/// Adding a widget is one file: conform, register the type, document its settings. It needs no
/// change to the config schema, because settings arrive as `WidgetSettings` and are parsed by the
/// widget itself.
@MainActor
public protocol NotchWidget: AnyObject {

    /// The name used in the config file: `widget = media`.
    ///
    /// Also the prefix for this widget's settings, so `media-artwork` reaches a widget of kind
    /// `media` as the setting `artwork`.
    static var kind: String { get }

    /// Build a widget from its settings.
    ///
    /// Throwing a `ConfigValueError` here surfaces as an ordinary config diagnostic, so a bad
    /// widget setting reads the same as any other bad line and does not take perch down.
    init(settings: WidgetSettings) throws

    /// Where this widget draws.
    var placement: Placement { get }

    /// Start doing work: subscribe, spawn processes, observe.
    ///
    /// Called when the widget becomes visible.
    func activate()

    /// Stop doing all work.
    ///
    /// Called when the widget is hidden, the display sleeps, or config reloads. This must release
    /// every timer, observer, and subprocess the widget owns — it is the whole reason perch can
    /// claim to cost nothing while idle, and a widget that leaks here quietly undoes that for the
    /// entire app.
    func deactivate()

    /// What to draw.
    var body: AnyView { get }
}

extension NotchWidget {
    /// The kind, reachable from an existential.
    public var kind: String { Self.kind }
}
