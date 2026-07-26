import CoreGraphics
import Testing

@testable import PerchCore

/// A 16" MacBook Pro, measured from real hardware via `NSScreen` rather than taken from spec
/// sheets: 1728x1117pt at 2x, with a 185x32pt camera housing whose auxiliary areas are one point
/// different in width.
///
/// The asymmetry is not a rounding artefact in the fixture — the display genuinely reports 771 and
/// 772 — and it puts the housing centre on a half point, which is precisely the case that exposes
/// alignment bugs. A tidied-up fixture would hide them.
private let macBookPro16 = ScreenGeometry(
    frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
    safeAreaTopInset: 32,
    auxiliaryTopLeftWidth: 771,
    auxiliaryTopRightWidth: 772,
    backingScaleFactor: 2
)

/// A 2560x1440 external display, positioned above the built-in one as macOS would arrange it.
private let externalDisplay = ScreenGeometry(
    frame: CGRect(x: 0, y: 1117, width: 2560, height: 1440),
    safeAreaTopInset: 0,
    auxiliaryTopLeftWidth: 0,
    auxiliaryTopRightWidth: 0,
    backingScaleFactor: 1
)

@Suite("Notch detection")
struct NotchDetectionTests {
    @Test("A display with a camera housing is detected as notched")
    func detectsHardwareNotch() {
        #expect(macBookPro16.hasHardwareNotch)
    }

    @Test("A display with no camera housing is not notched")
    func detectsNotchlessDisplay() {
        #expect(!externalDisplay.hasHardwareNotch)
    }

    @Test("A top inset without auxiliary areas is not a notch")
    func insetAloneIsNotANotch() {
        // Some external configurations report a non-zero top inset with no camera housing.
        // Requiring the auxiliary areas too is what keeps us from drawing a bogus hardware shape.
        var display = externalDisplay
        display.safeAreaTopInset = 24
        #expect(!display.hasHardwareNotch)
    }
}

@Suite("Notch geometry on notched displays")
struct HardwareNotchLayoutTests {
    @Test("The collapsed shape traces the camera housing exactly")
    func collapsedMatchesHardware() {
        let layout = NotchMetrics.resolve(for: macBookPro16)

        #expect(layout.kind == .hardware)
        #expect(layout.collapsedRect.width == 185)  // 1728 - 771 - 772
        #expect(layout.collapsedRect.height == 32)
        #expect(layout.collapsedRect.minY == 0)
    }

    @Test("The panel is pinned flush to the top of the display")
    func panelIsFlushWithTop() {
        let layout = NotchMetrics.resolve(for: macBookPro16)

        // AppKit's y axis points up, so the top edge of the display is frame.maxY.
        #expect(layout.panelRect.maxY == macBookPro16.frame.maxY)
    }

    @Test("The panel is tall enough for the notch plus the expanded body")
    func panelHeightCoversBothStates() {
        let expandedHeight: CGFloat = 180
        let layout = NotchMetrics.resolve(
            for: macBookPro16,
            options: NotchGeometryOptions(expandedHeight: expandedHeight)
        )

        let expected = macBookPro16.safeAreaTopInset + expandedHeight
        #expect(layout.panelRect.height == expected)
        #expect(layout.expandedRect.height == layout.panelRect.height)
    }

    @Test("Both shapes share a horizontal centre, so the notch grows in place")
    func shapesAreConcentric() {
        // Any drift here makes the notch slide sideways as it opens.
        let layout = NotchMetrics.resolve(for: macBookPro16)
        let tolerance = 0.5 / layout.scale

        #expect(abs(layout.collapsedRect.midX - layout.expandedRect.midX) <= tolerance)
        #expect(abs(layout.hardwareRect.midX - layout.expandedRect.midX) <= tolerance)
    }

    @Test("Side bleed widens the collapsed shape symmetrically")
    func sideBleedWidensCollapsedShape() {
        let plain = NotchMetrics.resolve(for: macBookPro16)
        let bled = NotchMetrics.resolve(
            for: macBookPro16,
            options: NotchGeometryOptions(collapsedSideBleed: 60)
        )

        #expect(bled.collapsedRect.width == plain.collapsedRect.width + 120)
        #expect(abs(bled.collapsedRect.midX - plain.collapsedRect.midX) < 0.5)
    }
}

@Suite("Notch geometry on notchless displays")
struct SyntheticNotchLayoutTests {
    @Test("A display with no housing gets a synthetic pill")
    func fallsBackToSyntheticPill() {
        let size = CGSize(width: 200, height: 32)
        let layout = NotchMetrics.resolve(
            for: externalDisplay,
            options: NotchGeometryOptions(syntheticNotchSize: size)
        )

        #expect(layout.kind == .synthetic)
        #expect(layout.collapsedRect.width == size.width)
        #expect(layout.collapsedRect.height == size.height)
    }

    @Test("The synthetic pill is centred on the display")
    func syntheticPillIsCentred() {
        let layout = NotchMetrics.resolve(for: externalDisplay)
        let pillCentreInGlobalSpace = layout.panelRect.minX + layout.collapsedRect.midX

        #expect(abs(pillCentreInGlobalSpace - externalDisplay.frame.midX) < 0.5)
    }

    @Test("Geometry is resolved in the display's own coordinate space")
    func respectsDisplayOrigin() {
        // The external display sits above the built-in one, so its origin is not zero. Getting
        // this wrong puts the panel on the wrong screen entirely.
        let layout = NotchMetrics.resolve(for: externalDisplay)

        #expect(layout.panelRect.maxY == externalDisplay.frame.maxY)
        #expect(layout.panelRect.minX >= externalDisplay.frame.minX)
    }
}

@Suite("Notch geometry edge cases")
struct NotchLayoutEdgeCaseTests {
    @Test("The panel never grows wider than the display")
    func panelIsClampedToDisplayWidth() {
        let layout = NotchMetrics.resolve(
            for: macBookPro16,
            options: NotchGeometryOptions(expandedWidth: 5000)
        )

        #expect(layout.panelRect.width <= macBookPro16.frame.width)
    }

    @Test("The panel stays on screen when the expanded shape is very wide")
    func panelStaysWithinDisplayBounds() {
        let layout = NotchMetrics.resolve(
            for: macBookPro16,
            options: NotchGeometryOptions(expandedWidth: 1700)
        )

        #expect(layout.panelRect.minX >= macBookPro16.frame.minX)
        #expect(layout.panelRect.maxX <= macBookPro16.frame.maxX)
    }

    @Test("Geometry is snapped to whole backing pixels")
    func geometryIsPixelAligned() {
        // An odd expanded width would otherwise land the centred shape on a half point and
        // produce a blurry edge on Retina.
        let layout = NotchMetrics.resolve(
            for: macBookPro16,
            options: NotchGeometryOptions(expandedWidth: 419)
        )

        for value in [layout.expandedRect.minX, layout.expandedRect.width, layout.panelRect.minX] {
            #expect((value * layout.scale).truncatingRemainder(dividingBy: 1) == 0)
        }
    }

    @Test("A zero backing scale does not produce degenerate geometry")
    func toleratesZeroBackingScale() {
        var display = macBookPro16
        display.backingScaleFactor = 0

        let layout = NotchMetrics.resolve(for: display)

        #expect(layout.scale == 1)
        #expect(layout.panelRect.width > 0)
        #expect(layout.panelRect.height > 0)
    }

    @Test("A negative expanded height collapses to the notch rather than inverting the panel")
    func toleratesNegativeExpandedHeight() {
        let layout = NotchMetrics.resolve(
            for: macBookPro16,
            options: NotchGeometryOptions(expandedHeight: -100)
        )

        #expect(layout.panelRect.height == 32)
    }
}

@Suite("Pixel alignment against real hardware")
struct PixelAlignmentTests {

    /// A spread of plausible display shapes, including ones that put the panel origin on a
    /// fraction — which is exactly where alignment bugs hide.
    private static let displays: [(name: String, screen: ScreenGeometry)] = [
        ("16-inch", macBookPro16),
        (
            "14-inch",
            ScreenGeometry(
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                safeAreaTopInset: 32,
                auxiliaryTopLeftWidth: 663,
                auxiliaryTopRightWidth: 663,
                backingScaleFactor: 2
            )
        ),
        (
            "odd width, asymmetric housing",
            ScreenGeometry(
                frame: CGRect(x: 0, y: 0, width: 1727, height: 1117),
                safeAreaTopInset: 32,
                auxiliaryTopLeftWidth: 770.5,
                auxiliaryTopRightWidth: 771.5,
                backingScaleFactor: 2
            )
        ),
        (
            "non-zero display origin",
            ScreenGeometry(
                frame: CGRect(x: -1728, y: 233, width: 1728, height: 1117),
                safeAreaTopInset: 32,
                auxiliaryTopLeftWidth: 771,
                auxiliaryTopRightWidth: 772,
                backingScaleFactor: 2
            )
        ),
        (
            "1x display",
            ScreenGeometry(
                frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                safeAreaTopInset: 24,
                auxiliaryTopLeftWidth: 627,
                auxiliaryTopRightWidth: 628,
                backingScaleFactor: 1
            )
        ),
    ]

    @Test("The panel origin lands on whole points")
    func panelOriginIsIntegral() {
        // AppKit rounds window origins to integers. A fractional origin is silently discarded and
        // every shape inside inherits the difference as a shift against the hardware.
        for (name, screen) in Self.displays {
            let panel = NotchMetrics.resolve(for: screen).panelRect
            #expect(
                panel.minX == panel.minX.rounded(),
                "\(name): panel x \(panel.minX) is not a whole point"
            )
            #expect(
                panel.minY == panel.minY.rounded(),
                "\(name): panel y \(panel.minY) is not a whole point"
            )
        }
    }

    @Test("The collapsed shape lands on the camera housing in global coordinates")
    func collapsedShapeLandsOnHousing() {
        // The invariant that actually matters: not what the local rect says, but where the shape
        // ends up on screen once the panel origin is applied.
        for (name, screen) in Self.displays {
            let layout = NotchMetrics.resolve(for: screen)
            let tolerance = 0.5 / layout.scale  // half a backing pixel; below this nothing renders

            let expectedLeft = screen.frame.minX + screen.auxiliaryTopLeftWidth
            let expectedRight = screen.frame.maxX - screen.auxiliaryTopRightWidth

            let actualLeft = layout.panelRect.minX + layout.collapsedRect.minX
            let actualRight = layout.panelRect.minX + layout.collapsedRect.maxX

            #expect(
                abs(actualLeft - expectedLeft) <= tolerance,
                "\(name): left edge at \(actualLeft), housing starts at \(expectedLeft)"
            )
            #expect(
                abs(actualRight - expectedRight) <= tolerance,
                "\(name): right edge at \(actualRight), housing ends at \(expectedRight)"
            )
        }
    }

    @Test("Every rendered length is a whole number of backing pixels")
    func lengthsArePixelAligned() {
        for (name, screen) in Self.displays {
            let layout = NotchMetrics.resolve(for: screen)
            let lengths: [(String, CGFloat)] = [
                ("collapsed.x", layout.collapsedRect.minX),
                ("collapsed.width", layout.collapsedRect.width),
                ("collapsed.height", layout.collapsedRect.height),
                ("expanded.x", layout.expandedRect.minX),
                ("expanded.width", layout.expandedRect.width),
            ]
            for (label, value) in lengths {
                let pixels = value * layout.scale
                #expect(
                    abs(pixels - pixels.rounded()) < 0.001,
                    "\(name): \(label) = \(value)pt is not a whole backing pixel"
                )
            }
        }
    }

    @Test("The hardware rect matches the camera housing regardless of bleed")
    func hardwareRectIgnoresBleed() {
        let plain = NotchMetrics.resolve(for: macBookPro16)
        let bled = NotchMetrics.resolve(
            for: macBookPro16,
            options: NotchGeometryOptions(collapsedSideBleed: 40)
        )

        #expect(plain.hardwareRect.width == bled.hardwareRect.width)
        #expect(bled.collapsedRect.width == bled.hardwareRect.width + 80)
    }
}

@Suite("Shoulder suppression")
struct ShoulderSuppressionTests {
    @Test("A collapsed shape with no bleed is reported as tracing hardware")
    func collapsedTracesHardware() {
        // Shoulders on this shape would be its only visible part: black wedges on the menu bar.
        let layout = NotchMetrics.resolve(for: macBookPro16)

        #expect(layout.tracesHardware(layout.collapsedRect))
    }

    @Test("An expanded shape is not reported as tracing hardware")
    func expandedDoesNotTraceHardware() {
        let layout = NotchMetrics.resolve(for: macBookPro16)

        #expect(!layout.tracesHardware(layout.expandedRect))
    }

    @Test("Bleed makes the collapsed shape stop tracing hardware")
    func bleedStopsTracingHardware() {
        let layout = NotchMetrics.resolve(
            for: macBookPro16,
            options: NotchGeometryOptions(collapsedSideBleed: 40)
        )

        #expect(!layout.tracesHardware(layout.collapsedRect))
    }

    @Test("A synthetic pill never counts as tracing hardware")
    func syntheticNeverTracesHardware() {
        // There is no housing to hide behind, so the shoulders are the blend into the top edge.
        let layout = NotchMetrics.resolve(for: externalDisplay)

        #expect(!layout.tracesHardware(layout.collapsedRect))
    }
}
