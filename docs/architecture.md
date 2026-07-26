# Architecture

Four modules, dependencies pointing one direction.

| Module | Role |
|---|---|
| `PerchCore` | Pure logic — geometry, config, state machine. No AppKit or SwiftUI. |
| `PerchMedia` | Now-playing state, behind a `MediaSource` protocol. |
| `PerchUI` | The panel, the shape, widgets, SwiftUI views. |
| `Perch` | Entry point and wiring. |

**`PerchCore` must never import a UI framework.** `make check` enforces it. That rule is what keeps
notch geometry, config parsing, and interaction state testable without a display — and it is the
one most easily broken by an absent-minded import.

The AppKit boundary is a single initialiser: `NSScreen` is flattened into a plain `ScreenGeometry`
struct, and everything downstream is arithmetic over values a test can fabricate.

## Decisions worth knowing

**The window never resizes.** `NotchMetrics` computes one fixed panel frame sized for the largest
state, and every state is drawn *inside* it. Resizing an `NSWindow` per frame is the usual source
of notch-app jank. Do not "simplify" this by sizing the window to the shape.

**The shape draws at absolute coordinates.** `NotchShape` is given the rect to draw and ignores its
own frame. The obvious alternative — size a frame to the notch plus shoulder overhang, then
position it — puts a child larger than its container into SwiftUI's layout system, where the origin
gets rounded to whole points. That silently shifted the panel half a point, and in another
arrangement clipped eight points off one side.

**Clicks pass through the empty area.** The panel is always at full size, so most of it is visually
empty. `NotchHostingView` restricts hit testing to the shape currently drawn, so the transparent
region behaves like it isn't there — and forwards everything else to SwiftUI, or widget controls go
dead.

**Notchless displays use the same path.** A display reporting no camera housing gets a synthetic
pill hanging from the top edge. Nothing upstream special-cases it.

**Idle cost is zero.** Nothing polls. Media state is pushed from a helper process, the config file
is watched with a kernel event source, and widgets release what they own when hidden. A widget that
needs to keep working while invisible opts in explicitly via `runsWhileHidden`, which is a promise
that its idle cost is negligible — measure before making it.

**The config struct is the schema.** Each stored property on `Config` is a key, its declared value
is the default, and its doc comment is the documentation. `--show-config --docs` is generated from
the same table the parser uses, so it cannot drift, and its output is a valid config file.

## AppKit traps this app is built on top of

Every one of these fails **silently** — no error, no warning, just wrong pixels or a dead control.

1. **`NSPanel.isFloatingPanel = true` assigns `level = .floating` (3) as a side effect.** Set it
   *before* your own level, or the panel drops below the menu bar (24).

2. **`NSWindow` constrains frames** so a title bar can never sit under the menu bar. Borderless
   panels must override `constrainFrameRect(_:to:)`, or the panel slides down by the menu bar
   height.

3. **`NSHostingView` applies the screen's safe-area inset**, pushing content below the notch — the
   exact region perch exists to draw in. `.ignoresSafeArea()` inside the SwiftUI tree cannot reach
   it; set `safeAreaRegions = []`. Also set `sizingOptions = []`, or SwiftUI's ideal size
   propagates back and resizes the window out from under you.

4. **SwiftUI rounds a positioned frame's origin to whole points.** See "absolute coordinates" above.

5. **A closure written inside a `@MainActor` type is inferred `@MainActor`-isolated.** Hand one to
   an API that knows nothing about actors — `DispatchSource.setEventHandler`, C callbacks — and it
   runs on the wrong executor, the isolation assertion fails, and the process dies with `SIGTRAP`.
   It compiles clean. Mark such closures `@Sendable` explicitly, then hop to the main actor inside.

6. **`NSView.mouseDown` must call `super`** for SwiftUI to see the event. SwiftUI does not create
   `NSView` subviews for buttons, so swallowing the event makes every control inert.

## Reading media on modern macOS

macOS 15.4 put `MediaRemote` behind an entitlement — third-party apps calling
`MRMediaRemoteGetNowPlayingInfo` get nothing. perch reads now-playing through
[mediaremote-adapter](https://github.com/ungive/mediaremote-adapter), vendored in `Vendor/`:
`/usr/bin/perl` carries an entitled bundle identifier, loads a helper framework, and streams JSON.

That is a loophole and Apple may close it. `MediaSource` exists so that when they do, only one
implementation changes. If media stops appearing after a macOS update, that is the first thing to
suspect — the adapter's own `test` command reports whether the entitlement still holds.

Upstream builds with CMake; perch compiles the same sources with clang from its own Makefile, so a
clone still needs nothing but `make`. See
[`Vendor/mediaremote-adapter/VENDORED.md`](../Vendor/mediaremote-adapter/VENDORED.md).
