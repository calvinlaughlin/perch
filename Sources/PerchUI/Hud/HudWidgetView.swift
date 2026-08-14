import PerchCore
import SwiftUI

/// The volume readout: a speaker glyph, a bar, and the level.
///
/// One view for both the panel and the peek, differing only in scale. A peek is glanced at, so it
/// drops the device name and the numeric readout unless asked for them; the bar is the part that
/// can be read in the half second it is up.
struct HudWidgetView: View {

    let widget: HudWidget
    let showsDevice: Bool
    let isPeek: Bool

    private var level: Double { widget.state?.effectiveLevel ?? 0 }
    private var isMuted: Bool { widget.state?.isMuted ?? false }

    var body: some View {
        HStack(spacing: PanelMetrics.columnGap) {
            Image(systemName: glyph)
                .font(.system(size: isPeek ? 13 : 15, weight: .medium))
                .foregroundStyle(.white)
                // A fixed width, so the bar does not shuffle sideways as the glyph changes between
                // one, two and three waves on its way up.
                .frame(width: isPeek ? 18 : 22, alignment: .leading)
                .accessibilityIdentifier("hud.glyph")

            bar
                .accessibilityIdentifier("hud.bar")

            if !isPeek || showsDevice {
                Text(caption)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .accessibilityIdentifier("hud.caption")
            }
        }
        .padding(.horizontal, isPeek ? 0 : PanelMetrics.panelInset)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hud.container")
        .accessibilityLabel(accessibilityLabel)
    }

    private var bar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.18))

                Capsule()
                    .fill(.white)
                    .frame(width: max(0, geometry.size.width * level))
            }
        }
        .frame(height: PanelMetrics.bar)
    }

    /// Matches the glyph macOS uses, so the replacement reads as the thing it replaced.
    private var glyph: String {
        if isMuted { return "speaker.slash.fill" }
        switch level {
        case ..<0.001: return "speaker.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    private var caption: String {
        if showsDevice, let name = widget.state?.deviceName, !name.isEmpty { return name }
        return "\(Int((level * 100).rounded()))%"
    }

    private var accessibilityLabel: String {
        isMuted ? "Volume muted" : "Volume \(Int((level * 100).rounded()))%"
    }
}
