# Agent Development Guide

A file for [guiding coding agents](https://agents.md/).

## Commands

- **Build:** `make` · **Run:** `make run` · **Format:** `make fmt`
- **Check:** `make check` — lint, arch guard, warnings-as-errors build, tests. What CI runs.
- **Test one suite:** `swift test --filter <name>`
- **Release:** `make release` — signs, notarises, staples

Hardware probes, local only, needing a notched display and granted permissions:

- `make probe` — drawn geometry against the real camera housing
- `make ui-probe` — the interface, through the accessibility tree. Read-only.
- `make ui-probe FULL=1` — also takes the pointer for ~40s and skips a track. Never run it while
  the user is working.

## Structure

- `Sources/PerchCore` — geometry, config, state. **No AppKit or SwiftUI**; `make check` enforces it.
- `Sources/PerchMedia` — now-playing, behind `MediaSource`
- `Sources/PerchUI` — panel, shape, widgets
- `Vendor/`, `tools/` — vendored adapter; probes and the icon generator

## Rules

- Warnings are errors.
- The panel never resizes; `NotchShape` draws at absolute coordinates. Do not reintroduce a sized
  frame — SwiftUI rounds a positioned origin to whole points and silently shifts the panel.
- `deactivate()` releases everything a widget owns.
- No `.xcodeproj`. Never open a PR or issue unless asked.

## Before claiming something works

Never on evidence a broken version would also produce. Don't read screenshots; sample pixels as
numbers. Drive real events, not `AXUIElementPerformAction`. Reintroduce the bug and watch the
check fail.

[CONTRIBUTING.md](CONTRIBUTING.md#verification) ·
[architecture + the six silent AppKit traps](docs/architecture.md#appkit-traps-this-app-is-built-on-top-of)
