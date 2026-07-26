# perch

A minimal, config-driven macOS notch app.

One plain-text config file, no settings UI, a small core, and a widget protocol so everything
above that core is modular. Think less "a thousand options in a preferences window" and more
"a file you edit and reload".

> **Status: working.** Hover the notch and it shows what is playing, with artwork and transport
> controls. Verified on hardware. Rough edges remain — see [Known gaps](#known-gaps).

## Configure it

```sh
$EDITOR ~/.config/perch/config     # or `perch --config-path`
```

```ini
open-on         = hover
open-delay      = 120ms
expanded-height = 180
```

Saved changes apply immediately. A typo warns and is skipped rather than taking the app down with
it. `perch --show-config --docs` prints every key with documentation, and its output is itself a
valid config file. See [docs/config.md](docs/config.md).

## Requirements

- macOS 14 or later
- Xcode 26 / Swift 6.2 to build

## Build

```sh
make          # assemble build/perch.app
make run      # build and launch, logs on stdout
make test     # unit tests
make install  # copy to /Applications
```

No `.xcodeproj` is committed. A clone builds with `make` and nothing else.

## Development

```sh
make check     # lint + build with warnings-as-errors + test — run before committing
make fmt       # reformat in place
make lint      # check formatting and rules, changing nothing

make probe     # measure drawn geometry against the real camera housing
make ui-probe  # drive the interface through the accessibility tree and assert it works
```

`probe` and `ui-probe` are local-only — they need a notched display, Screen Recording and
Accessibility permission, and something playing. They exist because unit tests cannot reach the
AppKit and event-delivery layers where this app's bugs actually live, and because a screenshot
cannot tell a working button from a dead one. Both have been verified to fail when their
respective bugs are reintroduced.

`make check` is exactly what CI runs, so a green local check means a green PR.

Formatting and linting use **`swift format`**, which ships inside the Swift 6 toolchain — no
Homebrew step, no pinned binary, nothing to drift. Config lives in [`.swift-format`](.swift-format).
Beyond the defaults it turns on `NeverForceUnwrap`, `NeverUseForceTry`,
`NeverUseImplicitlyUnwrappedOptionals`, `UseEarlyExits`, and the documentation-comment rules.

`AllPublicDeclarationsHaveDocumentation` is deliberately **off**: it demands prose on memberwise
initialisers and on SwiftUI's `body`, which is ceremony rather than explanation. Documenting the
non-obvious is a convention here, not a rule — comments should say *why*, and the code should be
clear enough to cover *what*.

Warnings are errors in `check` and in CI. A warning nobody fixes is a lie about the state of
the code.

## Design

Four modules, dependencies pointing one direction:

| Module | Role |
|---|---|
| `PerchCore` | Pure logic — geometry, config, state. No AppKit UI, fully testable. |
| `PerchMedia` | Now-playing source behind a protocol. |
| `PerchUI` | The panel, the shape, SwiftUI views. |
| `Perch` | Entry point and wiring. |

A few decisions worth knowing about, because they are not obvious and they are load-bearing:

**The window never resizes.** `NotchMetrics` computes one fixed panel frame sized for the fully
expanded shape, and the collapsed/expanded states are drawn *inside* it. Resizing an `NSWindow`
per frame is the usual source of notch-app jank.

**Clicks pass through the empty area.** Because the panel is always at full size, most of it is
visually empty. `NotchHostingView` restricts hit testing to the shape currently being drawn, so
the transparent region behaves like it isn't there.

**Notchless displays work through the same path.** When a display reports no camera housing,
`NotchMetrics` returns a synthetic pill hanging from the top edge. Nothing upstream special-cases it.

**Idle cost is zero.** No polling timers. State is pushed, and widgets release everything they own
when the notch is hidden. The config file is watched with a kernel event source, not polled.

**Widgets are the extension point.** A widget is one file: it declares a name, parses its own
settings, says where it draws, and starts and stops its own work. Adding one needs no change to the
config schema. See [docs/writing-a-widget.md](docs/writing-a-widget.md).

**The config struct is the schema.** Each stored property on `Config` is a key, its declared value
is the default, and its doc comment is the documentation — so `--show-config --docs` is generated
from the same table the parser uses and cannot drift.

### Three AppKit landmines, documented so nobody rediscovers them

Getting a window to sit *over* the menu bar took three non-obvious fixes, all of them silent
failures rather than errors:

1. `NSPanel.isFloatingPanel = true` has the side effect of assigning `level = .floating` (3).
   Setting it *after* your own level silently drops the window below the menu bar (24).
2. `NSWindow` constrains frames so a title bar can never sit under the menu bar. Borderless
   panels must override `constrainFrameRect(_:to:)` to opt out, or the panel slides down by the
   menu bar height.
3. `NSHostingView` applies the screen's safe-area inset — pushing content *below* the notch, the
   exact region we exist to draw in. `.ignoresSafeArea()` inside the SwiftUI tree cannot reach it;
   set `safeAreaRegions = []` on the hosting view. Also set `sizingOptions = []`, or SwiftUI's
   ideal size propagates back and resizes your window out from under you.

## License

MIT. See [LICENSE](LICENSE).

perch bundles [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD 3-Clause)
to read now-playing information, which macOS 15.4 put behind an entitlement. See
[NOTICES.md](NOTICES.md).

## Known gaps

- Not notarized, so a downloaded build is Gatekeeper-blocked. Build from source for now.
- The `peek` state exists in the state machine but nothing produces one yet.
- Multi-display handling is written but **unverified** — it needs a second display to exercise.
