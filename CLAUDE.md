# perch — working notes

A minimal, config-driven macOS notch app. One plain-text config file, no settings UI, a small
core, and a widget protocol above it.

## Commands

```sh
make check    # lint + warnings-as-errors build + tests. The gate. Run before committing.
make run      # build and launch with logs on stdout
make fmt      # reformat in place
```

CI runs `make check` plus a bundle-assembly smoke test. Green locally means green on CI.

## Architecture invariants

These are the load-bearing rules. Breaking one is the kind of thing that works fine in testing
and then falls apart on someone else's display.

**Dependencies point one way:** `PerchCore` ← `PerchUI` ← `Perch`, with `PerchMedia` beside
`PerchUI`. **`PerchCore` must never import AppKit or SwiftUI.** It is pure logic so that geometry,
config parsing, and state can be tested without a display. `make check` enforces this.

**The AppKit boundary is one initializer.** `NSScreen` is flattened into `ScreenGeometry` (plain
data) and everything downstream is arithmetic over structs. That is what makes `NotchMetrics`
testable against display shapes nobody has.

**The window never resizes.** `NotchMetrics` computes one fixed panel frame sized for the fully
expanded shape; collapsed and expanded are drawn *inside* it. Resizing an `NSWindow` per frame is
the standard source of notch-app jank. Do not "simplify" this by sizing the window to the shape.

**Zero timers at idle.** State is pushed, never polled. Widgets release everything they own in
`deactivate()`. Idle should measure 0.0% CPU.

## Three AppKit landmines

All three fail *silently* — no error, no warning, just wrong pixels. Rediscovering them costs
an afternoon.

1. `NSPanel.isFloatingPanel = true` assigns `level = .floating` (3) as a side effect. Set it
   **before** your own level or the panel drops below the menu bar (24).
2. `NSWindow` constrains frames so a title bar can never sit under the menu bar. Borderless
   panels must override `constrainFrameRect(_:to:)` to opt out.
3. `NSHostingView` applies the screen's safe-area inset — pushing content below the notch, the
   exact region we exist to draw in — and propagates SwiftUI's ideal size back into the window.
   Set both `safeAreaRegions = []` and `sizingOptions = []`.

## Verifying notch geometry

The notch is a **physical mask, not a framebuffer feature**: screenshots capture those pixels as
ordinary content. So `screencapture` plus pixel sampling is a reliable way to check placement
against real hardware.

```sh
screencapture -x -R740,0,250,50 /tmp/notch.png   # region is in points, capture is 2x
```

Then sample rows for the expected colour. Quit any other notch app first (NotchNook lives in
`~/Downloads` on this machine) — two apps drawing the same region makes every check ambiguous.

## Conventions

- Comments explain **why**, not what. The code covers what.
- Doc comments: one-line summary, blank `///` line, then detail. Enforced by lint.
- No force unwraps, no force try. Enforced by lint.
- Do not commit an `.xcodeproj`; the package and Makefile are the build system.
