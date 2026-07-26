import AppKit

/// The borderless window perch draws into.
///
/// It has to satisfy an unusual set of constraints simultaneously: sit *above* the menu bar,
/// follow the user across Spaces, and never steal focus from whatever they are typing into. Each
/// property below is load-bearing for one of those.
public final class NotchPanel: NSPanel {

    /// One step above `.mainMenu` (24), which puts us over the menu bar and the camera housing.
    ///
    /// Deliberately not `CGShieldingWindowLevel()` — that sits above screen savers and security
    /// prompts, which is antisocial for something that lives on screen permanently.
    static let notchWindowLevel = NSWindow.Level.statusBar

    public init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            // `.nonactivatingPanel` is the key to not stealing focus: clicking the notch will not
            // deactivate the frontmost app, so the user's text cursor stays where it was.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Order matters and is not obvious: `isFloatingPanel` has the side effect of assigning
        // `level = .floating` (3). Setting it after our own level would silently drop the panel
        // below the menu bar (24) and the top of the notch would render underneath it.
        isFloatingPanel = true
        level = Self.notchWindowLevel

        // Follow the user everywhere rather than belonging to one Space, and stay put when
        // Mission Control or a full-screen app takes over.
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]

        // The window is a transparent canvas; the notch shape is drawn by SwiftUI inside it.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        // Nothing about this window is user-manipulable.
        isMovable = false
        isMovableByWindowBackground = false
        isRestorable = false

        // Stay visible when perch is not the active app — the whole point is ambient presence.
        hidesOnDeactivate = false

        // We drive every transition with SwiftUI springs; AppKit's own fade would fight them.
        animationBehavior = .none
    }

    /// Never take key status.
    ///
    /// Widgets are click-to-act, and a text field in the notch would be worth revisiting this
    /// for — but until then, focus should never leave the user's real work.
    public override var canBecomeKey: Bool { false }

    public override var canBecomeMain: Bool { false }

    /// Opt out of AppKit's window-position clamping.
    ///
    /// By default `NSWindow` keeps a window's top edge below the menu bar so its title bar can
    /// never be dragged out of reach. That rule is exactly wrong here: the menu bar strip *is*
    /// where we need to draw. Without this override the panel silently slides down by the menu
    /// bar height and the notch shape floats below the hardware it is supposed to trace.
    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
