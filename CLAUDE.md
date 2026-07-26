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
4. SwiftUI rounds a positioned or offset frame's origin to **whole points**. Sizing a frame to the
   notch plus shoulder overhang and then placing it put a child larger than its container into the
   layout system, where that rounding shifted the panel half a point and, in another arrangement,
   clipped eight points off one side. `NotchShape` therefore draws at absolute coordinates within
   the full panel — there is no frame left to round. Do not reintroduce one.

## The Swift 6 concurrency trap

**A closure written inside a `@MainActor` type is inferred `@MainActor`-isolated.** Hand one to an
API that knows nothing about actors — `DispatchSource.setEventHandler`, C callbacks, older
delegate APIs — and it runs on the wrong executor, Swift's isolation assertion fails, and the
process dies with `SIGTRAP` in `_dispatch_assert_queue_fail`. It compiles clean with no warning.

Mark such closures `@Sendable` explicitly, which opts them out of inheriting isolation, then hop
to the main actor inside:

```swift
source.setEventHandler { @Sendable [weak self] in
    Task { @MainActor in self?.doTheThing() }
}
```

This cost an afternoon in `ConfigWatcher`. It presented as "live reload silently does not work",
because the crash happened before the first line of the handler and took the whole app with it.
When something concurrency-adjacent appears to do nothing, **check whether the process is still
alive** before assuming the event never fired — `kill -0 $PID`. The crash report
(`~/Library/Logs/DiagnosticReports/*.ips`) names the exact closure.

## Verifying anything

**Never claim something works on evidence that a broken version would also produce.** This is the
rule; the rest is how to follow it.

A "verified working" media widget shipped with every button dead. The evidence was: the process
existed, a screenshot contained the right words, idle CPU was 0%. All true. All equally true of a
build where clicks were swallowed before reaching any control.

### Do not verify by looking at screenshots

Reading a screenshot is unreliable twice over — the image is a steady state, and interpreting it
by eye is error-prone (it produced two wrong conclusions in one session, including a half-point
"drift" that was actually a bug in the measuring tool). Pixels are fine as *numbers*: sample them
and compare against computed values. That is what `make probe` does.

### Prefer the accessibility tree

`make ui-probe` reads the real view hierarchy — roles, values, identifiers, positions — and drives
it. This is machine-readable, stable across layout changes, and shows what is actually rendered
rather than a picture of it. Add `.accessibilityIdentifier(...)` to anything a probe should find.

### Drive with real events, not with API shortcuts

`AXUIElementPerformAction` invokes a control's action **directly**, bypassing event delivery. The
first version of `ui-probe` used it and **passed with the click bug still present**. Use the
accessibility tree to *locate* a control, then post real `CGEvent` clicks at that position. The
event path is usually where the bug is.

### Never post synthetic key events from a probe

`CGEvent` keystrokes go to whatever application is **frontmost**, not to the app under test. The
probe runs from a terminal, so a global Escape sent to dismiss a context menu went to the terminal
— cancelling the very command running the probe, which looked like tool calls being interrupted at
random for no reason.

Use targeted accessibility actions instead (`AXUIElementPerformAction`, `kAXCancelAction`). Mouse
events are safer because they are aimed at a screen position perch actually occupies, but the same
caution applies: click where perch is, never blindly.

### Every check must be shown to fail

An assertion that cannot fail is worse than none — it manufactures confidence. After writing one,
reintroduce the bug and confirm it goes red. Both probes have been verified this way:

| Reintroduced bug | Caught by |
|---|---|
| panel origin on backing pixels | `probe` — off-centre on 64 rows |
| shoulders while tracing hardware | `probe` — top row spans 761.5..965.5 |
| expanded centred on canvas | `probe` — off-centre on 64 rows |
| canvas too narrow for shoulders | `probe` — shoulders clipped |
| mouseDown swallowing clicks | `ui-probe` — playback unchanged, panel closed |

### Test transitions, not just steady state

Bugs that live in *timing* — content arriving after the surface, artwork reloading on reopen — are
invisible in a settled frame. Sample during the change: burst-capture across an animation, or
reopen after a short delay and assert content is already there.

## Verifying notch geometry

**Run `make probe` after touching geometry, the panel, or the shape.** It launches perch itself,
captures a clean baseline, and diffs — so it does not care what is behind the notch or what colour
perch draws in. It checks **both** states: collapsed must trace the housing and never spill past
it; expanded must stay centred on the housing with its shoulders intact.

Checking both matters. An earlier version checked only the collapsed state and passed happily
while the expanded panel was clipped by eight points on one side.

Two rules learned the hard way:

- **Capture origins must be whole points.** `screencapture -R` floors fractional coordinates, so a
  fractional origin offsets every measurement by half a point — which reads as a bug in perch when
  it is a bug in the ruler.
- **Fixtures come from `NSScreen`, not spec sheets.** The 16" housing is 185x32pt here with
  auxiliary areas a point apart, not the 220x38 the internet claims. That asymmetry puts the
  housing centre on a half point, which is exactly the case that exposes alignment bugs.

This exists because unit tests structurally cannot catch this class of bug. `NotchMetrics` can
compute perfect numbers and AppKit will still round the window origin to a whole point, apply a
safe-area inset, or resize the window to SwiftUI's ideal size — silently, with every test green.
Two real bugs shipped that way: a half-point leftward shift from a fractional window origin, and
shoulders painting black wedges on the menu bar beside the notch.

The invariant the probe checks is one-sided on purpose. A row *narrower* than the housing is fine
— the housing is opaque, so anything inside it is invisible, which is what the collapsed shape's
bottom corner rounding looks like from the outside. A row *wider* than the housing is a defect by
construction, because those pixels land where the user can see them.

### Doing it by hand

The notch is a **physical mask, not a framebuffer feature**: screenshots capture those pixels as
ordinary content. So `screencapture` plus pixel sampling is a reliable way to check placement
against real hardware.

```sh
screencapture -x -R740,0,250,50 /tmp/notch.png   # region is in points, capture is 2x
```

Then sample rows for the expected colour. Quit any other notch app first (NotchNook lives in
`~/Downloads` on this machine) — two apps drawing the same region makes every check ambiguous.

## Widgets

A widget is one file conforming to `NotchWidget` plus one `WidgetRegistry.shared.register` line.
Settings are parsed by the widget from `WidgetSettings`, so adding one never touches `Config`.

The protocol is `NotchWidget`, not `Widget`: SwiftUI declares its own `Widget` for WidgetKit, and
every widget file imports SwiftUI. Do not "fix" the name.

`deactivate()` must release every timer, task, observer, and subprocess. The zero-idle-cost claim
is the sum of every widget honouring that. `WidgetHost` guarantees calls are balanced.

## Conventions

- Comments explain **why**, not what. The code covers what.
- Doc comments: one-line summary, blank `///` line, then detail. Enforced by lint.
- No force unwraps, no force try. Enforced by lint.
- Do not commit an `.xcodeproj`; the package and Makefile are the build system.
