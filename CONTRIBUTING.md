# Contributing

## Getting set up

```sh
git clone https://github.com/calvinlaughlin/perch.git
cd perch
make check       # lint + build with warnings-as-errors + tests
make run         # build and launch with logs on stdout
```

Requires macOS 14+ and Xcode 26 / Swift 6.2. Nothing else — no Homebrew, no CMake, no
`.xcodeproj`. Formatting uses `swift format` from the toolchain, so there is no linter version to
pin or drift.

`make check` is exactly what CI runs, so a green local check means a green PR.

## Warnings are errors

Both locally and in CI. A warning nobody fixes is a lie about the state of the code.

`AllPublicDeclarationsHaveDocumentation` is deliberately **off** — it demands prose on memberwise
initialisers and on SwiftUI's `body`, which is ceremony rather than explanation. Documenting the
non-obvious is a convention here, not a rule: comments should say *why*, and the code should be
clear enough to cover *what*.

## Verification

perch has three layers, because unit tests structurally cannot reach where its bugs live.

| | Covers | Runs in CI |
|---|---|---|
| `make test` | Geometry, config parsing, state machine, stream decoding | yes |
| `make probe` | What is actually drawn, measured against the real camera housing | no |
| `make ui-probe` | Whether the interface works, driven through the accessibility tree | no |

The probes need a notched display, Screen Recording and Accessibility permission, and something
playing — none of which a CI runner has. **`make ui-probe` takes over your mouse for about 40
seconds**; do not run it mid-work.

### Rules that were learned the hard way

**Never claim something works on evidence a broken version would also produce.** A media widget was
once called working because a process existed, a screenshot contained the right words, and idle CPU
was 0%. All true. Every button was dead.

**Do not verify by reading screenshots.** They show a steady state, and interpreting them by eye is
unreliable. Pixels are fine as *numbers* — sample them and compare against computed values, which
is what `make probe` does.

**Drive real event paths, not API shortcuts.** `AXUIElementPerformAction` invokes a control's
action directly, bypassing event delivery. The first version of `ui-probe` used it and passed with
the click bug still present. Use accessibility to *locate* a control, then post a real `CGEvent`
click at that position.

**Never post synthetic key events from a probe.** They go to whatever app is frontmost, not the app
under test. A global Escape sent to dismiss a menu once cancelled the terminal command running the
probe.

**Every check must be shown to fail.** After writing an assertion, reintroduce the bug and confirm
it goes red. An assertion that cannot fail manufactures confidence.

### What the probes cannot see

They measure structure and geometry: where a view is, what it contains, whether pressing it changes
anything. They say nothing about how something is *drawn*. A text label shimmering as it fades — a
real bug that shipped here — moves zero points and is invisible to all of it. Rendering-level
polish still needs eyes.

## Adding a widget

One file plus one registration line. See **[docs/writing-a-widget.md](docs/writing-a-widget.md)**.

The part that matters is `deactivate()`: it must release every timer, task, observer and
subprocess the widget owns. perch's claim to cost nothing while idle is exactly the sum of every
widget honouring that.

## The icon

Drawn in code — `tools/MakeIcon.swift`, run by `make icon` — rather than committed as a binary
asset. It renders every size an icon has to survive, from 1024px down to 16px, so a colour or
proportion change is a one-line diff instead of an opaque file nobody can edit.

Two things it learned the hard way: a mark must be attached to an edge to read as a *notch* rather
than a container, and it has to be dark, because a white one merges with the transparent area
outside the plate and reads as a bite taken out of the icon.

## Architecture

Four modules, dependencies pointing one way. `PerchCore` must never import AppKit or SwiftUI —
`make check` enforces it — because that is what keeps geometry, config and state testable without
a display.

Details, and the AppKit traps this app is built on top of:
**[docs/architecture.md](docs/architecture.md)**.

## Commits

Explain *why*, not what the diff already shows. Where a fix is non-obvious, say what was actually
wrong and how it presented — several of the trickiest bugs here looked like something else
entirely, and the commit log is where that knowledge lives.
