import Foundation
import PerchCore
import SwiftUI

/// Shows the time.
///
/// Deliberately the simplest useful widget, and the second one written — the widget protocol's
/// claim to be a real extension point is only worth anything once something other than media has
/// gone through it. It is also the first widget designed for the collapsed strip, which is where
/// the flanking layout gets exercised at all.
@MainActor
@Observable
public final class ClockWidget: NotchWidget {

    public static let kind = "clock"

    public static let summary = "Shows the time."

    public static let settings: [WidgetSetting] = [
        WidgetSetting(
            name: "placement", syntax: "leading | trailing | expanded", defaultValue: "trailing",
            documentation: "Where the widget draws. The strips need collapsed-bleed to have room."),
        WidgetSetting(
            name: "seconds", syntax: "true | false", defaultValue: "false",
            documentation: "Include seconds."),
        WidgetSetting(
            name: "24-hour", syntax: "true | false", defaultValue: "false",
            documentation: "Use a 24-hour clock."),
    ]

    public let placement: Placement

    private let showsSeconds: Bool
    private let usesTwentyFourHour: Bool

    private var ticker: Task<Void, Never>?

    fileprivate private(set) var now = Date()

    public init(settings: WidgetSettings) throws {
        placement = try settings.enumeration("placement", default: .trailing)
        showsSeconds = try settings.bool("seconds", default: false)
        usesTwentyFourHour = try settings.bool("24-hour", default: false)
    }

    public func activate() {
        guard ticker == nil else { return }

        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.now = Date()

                // Sleep to the next boundary rather than a fixed interval, so the display changes
                // when the clock does instead of drifting up to a whole unit behind it.
                let unit: TimeInterval = self?.showsSeconds == true ? 1 : 60
                let next = (Date().timeIntervalSince1970 / unit).rounded(.down) * unit + unit
                let delay = max(0.05, next - Date().timeIntervalSince1970)
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    public func deactivate() {
        ticker?.cancel()
        ticker = nil
    }

    public var body: AnyView {
        AnyView(ClockWidgetView(widget: self, format: format))
    }

    private var format: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime
            .hour(
                usesTwentyFourHour ? .twoDigits(amPM: .omitted) : .defaultDigits(amPM: .abbreviated)
            )
            .minute(.twoDigits)
        if showsSeconds { style = style.second(.twoDigits) }
        return style
    }
}

private struct ClockWidgetView: View {
    let widget: ClockWidget
    let format: Date.FormatStyle

    var body: some View {
        Text(widget.now, format: format)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(1)
            .fixedSize()
            .accessibilityIdentifier("clock.time")
    }
}
