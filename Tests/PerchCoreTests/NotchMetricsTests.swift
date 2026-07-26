import CoreGraphics
import Testing

@testable import PerchCore

/// A 16" MacBook Pro: 3456x2234 backing pixels at 2x, 220x38pt camera housing.
private let macBookPro16 = ScreenGeometry(
    frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
    safeAreaTopInset: 38,
    auxiliaryTopLeftWidth: 754,
    auxiliaryTopRightWidth: 754,
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
        #expect(layout.collapsedRect.width == 220)  // 1728 - 754 - 754
        #expect(layout.collapsedRect.height == 38)
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
        let layout = NotchMetrics.resolve(for: macBookPro16)

        #expect(abs(layout.collapsedRect.midX - layout.expandedRect.midX) < 0.5)
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

        #expect(layout.panelRect.height == 38)
    }
}
