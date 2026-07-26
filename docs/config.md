# Configuration

perch reads one plain-text file:

```
$XDG_CONFIG_HOME/perch/config      # or ~/.config/perch/config
```

`perch --config-path` prints the exact location. On first run perch writes an annotated starter
config there listing every setting, every available widget, and what each accepts — so the file
itself is the reference.

**Everything in it is commented out.** A file pinning today's values would freeze them: a later
perch that improved a default would never reach anyone who had opened their config once.
Uncommenting a line is how you say you disagree with a default.

**The file is optional.** The defaults are what perch is meant to look like; the file is for
disagreeing with one of them, not a prerequisite for a working app. Changes apply the moment you
save — there is no restart and no reload command.

## Syntax

```ini
# Lines starting with # are comments.

open-on    = hover        # spaces around = are optional
open-delay = 120ms

expanded-width = "420"    # quotes are optional, and only matter for
                          # values with spaces or a literal #
corner-radius  =          # empty value restores the default
```

That is the entire grammar. Keys are flat and hyphenated — there are no sections and no nesting.
Settings belonging to one widget will namespace themselves with a prefix (`media-artwork`) rather
than introducing syntax for it.

A key set twice takes its last value, so you can paste a block at the bottom of the file to
override what came above it.

## Mistakes are not fatal

A key perch does not recognise, or a value it cannot parse, is reported and skipped. Everything
else in the file still applies, and perch keeps running.

```
~/.config/perch/config:12: warning: unknown key 'expanded-heigth' — did you mean 'expanded-height'?
~/.config/perch/config:4: warning: open-on: expected one of: hover, click, never — found 'sideways'
```

This matters because the file is reloaded as you save it. A stricter loader would leave you
staring at a broken notch every time you typed a character in the wrong place.

Diagnostics go to stderr in `path:line: severity: message` form, so `make run` shows them in the
terminal and editors can jump straight to the line.

## Seeing the current settings

```sh
perch --show-config          # every key and its active value
perch --show-config --docs   # the same, with documentation
```

The output is itself a valid config file — you can redirect it straight to
`~/.config/perch/config` and start editing. It is generated from the same table the parser uses,
so it cannot drift out of date with what perch actually does.

## Keys

### Interaction

| Key | Accepts | Default |
|---|---|---|
| `open-on` | `hover` \| `click` \| `never` | `hover` |
| `open-delay` | duration | `120ms` |

`open-on = never` leaves the notch inert to the pointer; widgets can still peek.

`open-delay` is how long the pointer must rest on the notch before it opens, which stops it flying
open every time you cross the top of the screen on the way to the menu bar. Ignored unless
`open-on` is `hover`. Durations are written `120ms`, `1.5s`, or a bare number read as milliseconds.

Clicking toggles the panel even when `open-on` is `hover`, so there is always a way to dismiss it
without moving the pointer off it.

### Announcements

The notch can briefly enlarge on its own to announce something — a track change — then revert.
It never interrupts a panel you opened yourself.

| Key | Accepts | Default |
|---|---|---|
| `peek-on-track-change` | `true` \| `false` | `true` |
| `peek-duration` | duration | `2s` |
| `peek-height` | points | `64` |

A peek shows a compact form — artwork and title, no controls — because it is glanced at rather
than used. `peek-on-track-change = false` turns it off without affecting anything else.

### Displays

| Key | Accepts | Default |
|---|---|---|
| `display` | `notched` \| `main` \| *name* | `notched` |

`notched` prefers a display with a camera housing, so plugging in a monitor does not drag perch
off the built-in screen. `main` follows the menu bar. Anything else matches a display name
case-insensitively on any part of it — `LG` matches "LG ULTRAWIDE". A named display that is not
connected falls back to `notched` rather than leaving perch invisible.

### Shape

| Key | Accepts | Default |
|---|---|---|
| `expanded-height` | points | `128` |
| `expanded-width` | points | `420` |
| `corner-radius` | points | `24` |
| `collapsed-corner-radius` | points | `14` |
| `collapsed-bleed` | points | `0` |
| `shoulder-radius` | points | `10` |

`expanded-width` is clamped to the display width.

`collapsed-bleed` widens the collapsed shape past the camera housing on each side, letting widgets
spill into the dead space beside it. `0` traces the hardware exactly.

`shoulder-radius` is the concave flare where an open panel meets the top of the display, which is
what makes it read as carved out of the bezel rather than pasted on. It is suppressed
automatically whenever the shape is tracing the housing exactly — there it would have nothing to
blend into and would just paint onto the menu bar beside the notch.

### Debugging

| Key | Accepts | Default |
|---|---|---|
| `debug-shape` | `true` \| `false` | `false` |

The notch is physically black and so is the shape perch draws, which makes the collapsed state
invisible by design and impossible to eyeball. `debug-shape = true` draws it tinted and outlined
instead, so you can see exactly what geometry is being used.

## Widgets

Widgets are declared with a repeated key, and shown in the order declared:

```ini
widget = media
```

`widget =` with no value clears the list, which lets a pasted block start from nothing without
knowing what came above it.

Each widget's settings are prefixed with its name. A prefixed key whose widget has not been
declared is reported, since it would otherwise silently do nothing:

```
~/.config/perch/config:8: warning: unknown key 'clock-format' — if this is a widget setting,
declare the widget first with 'widget = clock'
```

Settings may appear above the `widget =` line that gives them meaning.

**The media widget is enabled by default**, so perch shows what is playing with no config file at
all.

### media

Shows the current track with transport controls, for any player the system knows about — Music,
Spotify, browsers, anything that registers with macOS.

| Key | Accepts | Default |
|---|---|---|
| `media-placement` | `leading` \| `trailing` \| `expanded` | `expanded` |
| `media-artwork` | `true` \| `false` | `true` |
| `media-artwork-size` | points | `56` |

Album art is decoded off the main thread and downsampled to the size actually drawn, so a 3000px
cover never becomes a 3000px bitmap.

The widget only runs while it can be seen. With the default `expanded` placement, nothing is
started until you open the notch, and everything is torn down when you close it — including the
helper process that reads playback state.

#### A note on how this works

macOS 15.4 put `MediaRemote` behind an entitlement, so apps can no longer simply ask what is
playing. perch reads it through a bundled helper loaded by `/usr/bin/perl`, whose bundle
identifier is still entitled. That is a loophole and Apple may close it.

If media stops appearing after a macOS update, that is the first thing to suspect. perch logs a
diagnostic when the helper repeatedly fails rather than relaunching it forever.

### clock

Shows the time. Defaults to the collapsed strip, so it is visible without opening the notch.

| Key | Accepts | Default |
|---|---|---|
| `clock-placement` | `leading` \| `trailing` \| `expanded` | `trailing` |
| `clock-seconds` | `true` \| `false` | `false` |
| `clock-24-hour` | `true` \| `false` | `false` |

A strip widget needs somewhere to go: `collapsed-bleed` must be non-zero, or the collapsed shape
traces the camera housing exactly and there is no room beside it.

```ini
collapsed-bleed = 90
widget = clock
clock-placement = trailing
```

## Only one perch

perch takes an exclusive lock on `perch.lock` in its config directory at startup. A second copy
prints which process holds it and exits rather than drawing a second panel over the same notch.
The lock is held by the kernel, so it is released even if perch crashes — there is no stale lock
to clear.

## Displays without a notch

perch works on external monitors. When a display reports no camera housing it gets a synthetic
pill hanging from the top edge instead, and every setting above applies to it unchanged.
