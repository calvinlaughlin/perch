# perch

[![CI](https://github.com/calvinlaughlin/perch/actions/workflows/ci.yml/badge.svg)](https://github.com/calvinlaughlin/perch/actions/workflows/ci.yml)

A minimal, config-driven macOS notch app.

One plain-text config file, no settings UI, and a widget protocol so everything above a small core
is modular. Less "a thousand options in a preferences window", more "a file you edit and it
reloads".

![perch: hovering the notch opens the media panel; changing track makes it announce the new one](docs/images/demo.gif)

<sub>Hovering opens the panel. Moving away closes it. Changing track makes the notch announce
the new one on its own, then revert.</sub>

## What it does

- **Shows what is playing** — artwork, title, artist, transport controls, for any player macOS
  knows about. Hover the notch and it opens.
- **Announces track changes** — the notch briefly swells to tell you what came on, then reverts.
- **Stays out of the way** — collapsed, it traces the camera housing exactly and is invisible.
  Clicks pass straight through it. Nothing polls; it costs 0% CPU sitting there.
- **Is configured by a text file** that applies the moment you save it.
- **Works on displays without a notch** — external monitors get a pill hanging from the top edge.

## Install

Download the latest release, unzip, and drag `perch.app` to `/Applications`. It is signed and
notarized, so it opens without a Gatekeeper warning.

Or build it:

```sh
git clone https://github.com/calvinlaughlin/perch.git
cd perch
make && make install
open -a perch
```

Right-click the notch for configuration, **Open at Login**, and quit.

Requires **macOS 14+** and **Xcode 26 / Swift 6.2** to build. No `.xcodeproj` is committed — a
clone builds with `make` and nothing else.

## Configure

```sh
perch --edit-config          # or edit ~/.config/perch/config directly
```

```ini
open-on         = hover      # hover | click | never
open-delay      = 120ms
expanded-height = 88

widget          = media
media-artwork   = true
```

Saved changes apply immediately. A typo is reported and skipped rather than taking the app down:

```
~/.config/perch/config:12: warning: unknown key 'expanded-heigth' — did you mean 'expanded-height'?
```

`perch --show-config --docs` prints every key with documentation, and its output is itself a valid
config file. Full reference: **[docs/config.md](docs/config.md)**.

## Widgets

Two ship today — `media` and `clock`. A widget is one file: it declares a name, parses its own
settings, says where it draws, and starts and stops its own work. Adding one needs no change to
the config schema.

```ini
collapsed-bleed = 90         # make room beside the housing
widget          = clock
clock-placement = trailing
```

See **[docs/writing-a-widget.md](docs/writing-a-widget.md)**.

## Status

Working and in daily use, but early. Known gaps:

- Only two widgets so far.
- No app icon.
- Rendering-level polish (as opposed to layout) is not covered by the automated checks — see
  [CONTRIBUTING.md](CONTRIBUTING.md#what-the-probes-cannot-see).

## Development

```sh
make check       # lint + build with warnings-as-errors + tests. What CI runs.
make run         # build and launch with logs on stdout
make probe       # verify drawn geometry against the real camera housing
make ui-probe    # drive the interface through the accessibility tree
```

Architecture, the AppKit traps this app is built on top of, and how verification works:
**[CONTRIBUTING.md](CONTRIBUTING.md)** and **[docs/architecture.md](docs/architecture.md)**.

## License

MIT — see [LICENSE](LICENSE).

perch bundles [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD 3-Clause)
to read now-playing information, which macOS 15.4 put behind an entitlement. See
[NOTICES.md](NOTICES.md).
