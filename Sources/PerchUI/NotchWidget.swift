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
/// How a widget asks the notch to announce something.
///
/// Handed to widgets that want it, so a widget can request attention without knowing anything
/// about the controller, the state machine, or what else is on screen. Whether the request is
/// honoured is not the widget's decision: a peek never interrupts a panel the user opened.
@MainActor
public protocol NotchAttention: AnyObject, Sendable {
    /// Ask the notch to peek. Ignored if the user already has it open.
    func requestPeek()
}

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

    /// What to draw during a peek, or `nil` if this widget has nothing to announce.
    ///
    /// **`nil` by default, and that is the point.** A peek is an announcement — the notch swelling
    /// unbidden to say something changed — so appearing in one is opt-in, exactly like the
    /// `runsWhileHidden` a widget needs in order to notice a change in the first place. A widget
    /// that has never announced anything has nothing to say in the two seconds a peek lasts, and
    /// putting it there means a track change hands you a scratchpad.
    ///
    /// Override to return a compact form of what just changed. A peek is glanced at, not read.
    var peekBody: AnyView? { get }

    /// A one-line description, for the generated starter config.
    static var summary: String { get }

    /// The settings this widget accepts, documented for the generated starter config.
    static var settings: [WidgetSetting] { get }

    /// Whether this widget keeps working while it cannot be seen.
    ///
    /// `false` by default, and that default is the point: a hidden widget doing nothing is what
    /// lets perch cost nothing while it sits on the bezel.
    ///
    /// A widget that *announces* things has to opt in, because it cannot notice a change it is not
    /// watching for. Opting in is a promise that its idle cost is genuinely negligible — measure
    /// it before making that promise.
    var runsWhileHidden: Bool { get }

    /// Receive a handle for requesting peeks.
    ///
    /// Optional: widgets that never announce anything can ignore it, which is why there is a
    /// default implementation that does nothing.
    func attach(attention: any NotchAttention)

    /// Note that this widget's `body` is, or is no longer, on screen.
    ///
    /// Not the same question as `activate`. A widget with `runsWhileHidden` stays active behind a
    /// closed notch precisely so it can keep watching — but *watching* is not *drawing*, and
    /// anything that only exists to move pixels has no business running when there are no pixels:
    /// an animation nobody can see costs exactly as much as one they can.
    ///
    /// Called with `false` before `deactivate`, so a widget that only implements the latter is
    /// still correct. Default does nothing.
    func setVisible(_ visible: Bool)
}

extension NotchWidget {
    public func attach(attention: any NotchAttention) {}
    public func setVisible(_ visible: Bool) {}
    public var runsWhileHidden: Bool { false }
    public var peekBody: AnyView? { nil }
    public static var summary: String { "" }
    public static var settings: [WidgetSetting] { [] }
}

extension NotchWidget {
    /// The kind, reachable from an existential.
    public var kind: String { Self.kind }
}
