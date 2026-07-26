# Configuration

perch reads one plain-text file:

```
$XDG_CONFIG_HOME/perch/config      # or ~/.config/perch/config
```

`perch --config-path` prints the exact location.

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

### Shape

| Key | Accepts | Default |
|---|---|---|
| `expanded-height` | points | `180` |
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

## Displays without a notch

perch works on external monitors. When a display reports no camera housing it gets a synthetic
pill hanging from the top edge instead, and every setting above applies to it unchanged.
