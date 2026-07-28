import CoreGraphics
import Foundation

/// Every user-settable option in perch.
///
/// This struct is the schema. Each stored property corresponds to one key in the config file, its
/// declared value is the default, and its doc comment is the user-facing documentation. Keeping
/// those three things in one place is what stops the file format, the code, and the docs from
/// drifting apart — and it is what makes `perch +show-config --default --docs` possible later.
///
/// Keys are flat and hyphenated (`open-delay`, not `notch.open.delay`). A flat namespace means one
/// grammar with no nesting rules, and per-widget options namespace themselves with a prefix
/// (`media-artwork`).
///
/// **Zero configuration must be good configuration.** The defaults below are what perch looks like
/// with no config file at all, and that has to be a state worth shipping — the file is for people
/// who disagree with a default, not a prerequisite for a working app.
public struct Config: Equatable, Sendable {

    // MARK: - Interaction

    /// What opens the notch: `hover`, `click`, or `never`.
    ///
    /// `never` leaves the notch inert to the pointer; widgets can still peek.
    public var openOn: OpenTrigger = .hover

    /// How long the pointer must rest on the notch before it opens.
    ///
    /// Guards against the notch flying open every time the pointer crosses the top of the screen
    /// on its way to the menu bar. Ignored when `open-on` is not `hover`.
    public var openDelay: Duration = .milliseconds(120)

    /// Which display perch lives on.
    ///
    /// `notched` picks a display with a camera housing, so plugging in a monitor does not drag the
    /// notch off the built-in screen just because the external one became the main display.
    /// `main` follows the menu bar. Any other value matches a display by name, case-insensitively,
    /// on any part of it — `LG` is enough for "LG ULTRAWIDE".
    ///
    /// A display that no longer exists falls back to the `notched` behaviour rather than leaving
    /// perch invisible.
    public var display: String = "notched"

    /// Which events make the trackpad tap: `never`, `open`, `peek`, or `all`.
    ///
    /// Off by default, and deliberately so. The notch opens on hover, which means every trip to
    /// the menu bar passes over it — a tap on each of those would be a thing you feel all day
    /// without having asked for it. Haptics are also hardware the user may not have: nothing
    /// happens on a Mac without a Force Touch trackpad, or with system haptics switched off, so a
    /// default of `all` would be inert for some people and intrusive for the rest. Opting in is
    /// the only setting that is right for everyone.
    public var haptics: HapticTrigger = .never

    /// How a tap feels.
    ///
    /// `alignment` is the lightest of the three, and the notch opening is a small event.
    public var hapticPattern: HapticPattern = .alignment

    // MARK: - Shape

    /// Height of the expanded panel below the notch, in points.
    ///
    /// Sized to hug one row of content. Raise it if a widget needs more room.
    public var expandedHeight: CGFloat = 88

    /// Width of the expanded panel, in points.
    ///
    /// Clamped to the display width.
    public var expandedWidth: CGFloat = 420

    /// Height of the peek panel below the notch, in points.
    ///
    /// A peek announces something you did not ask to see, so it is deliberately smaller than the
    /// panel you open yourself — room for artwork and a title, not for controls.
    public var peekHeight: CGFloat = 64

    /// How long a peek stays up before reverting on its own.
    public var peekDuration: Duration = .seconds(2)

    /// Whether a track change makes the notch peek.
    public var peekOnTrackChange: Bool = true

    /// Corner radius of the expanded panel's bottom corners, in points.
    public var cornerRadius: CGFloat = 24

    /// Radius of the concave shoulders where the shape meets the top of the display, in points.
    ///
    /// Makes an open panel look carved out of the bezel rather than pasted onto it. Suppressed
    /// automatically when the shape is tracing the camera housing exactly — there the shoulders
    /// would have nothing to blend into and would just paint onto the menu bar beside the notch.
    public var shoulderRadius: CGFloat = 10

    /// Corner radius of the collapsed shape's bottom corners, in points.
    ///
    /// Defaults to roughly the curvature of the physical camera housing, so the collapsed state
    /// disappears into the hardware.
    public var collapsedCornerRadius: CGFloat = 14

    /// Extra width added to each side of the collapsed shape, in points.
    ///
    /// Lets widgets spill into the dead space beside the camera housing. `0` traces the hardware
    /// exactly.
    public var collapsedBleed: CGFloat = 0

    // MARK: - Widgets

    /// Which widgets to show, in declaration order.
    ///
    /// Written as a repeated key — `widget = media` — because a list of things is the one shape a
    /// flat `key = value` grammar cannot express otherwise, and repeating a key is how every
    /// config format of this kind does it. `widget =` with no value clears the list.
    ///
    /// Defaults to the media widget: zero configuration has to be worth shipping, and a notch that
    /// shows nothing at all is not.
    public var widgets: [String] = ["media"]

    /// Per-widget settings, keyed by widget kind then setting name.
    ///
    /// Populated from prefixed keys: `media-artwork = true` becomes
    /// `widgetSettings["media"]["artwork"] = "true"`. Values stay as written and are parsed by the
    /// widget, so `PerchCore` never has to know what settings exist.
    public var widgetSettings: [String: [String: String]] = [:]

    /// The settings for one widget kind, empty if it has none.
    public func settings(for kind: String) -> WidgetSettings {
        WidgetSettings(kind: kind, values: widgetSettings[kind] ?? [:])
    }

    // MARK: - Debugging

    /// Draw the notch shape tinted and outlined instead of black.
    ///
    /// The notch is physically black and so is the shape, which makes the collapsed state
    /// impossible to eyeball. Turn this on to see exactly what geometry is being drawn.
    public var debugShape: Bool = false

    public init() {}

    /// The subset of config that the haptic engine needs.
    public var hapticPolicy: HapticPolicy {
        HapticPolicy(trigger: haptics, pattern: hapticPattern)
    }

    /// The subset of config that `NotchMetrics` needs.
    ///
    /// Keeps the geometry layer's input a small explicit struct rather than the whole config, so
    /// adding an unrelated key can never change how geometry resolves.
    public var geometryOptions: NotchGeometryOptions {
        NotchGeometryOptions(
            expandedHeight: expandedHeight,
            expandedWidth: expandedWidth,
            collapsedSideBleed: collapsedBleed,
            shoulderRadius: shoulderRadius,
            peekHeight: peekHeight
        )
    }
}
