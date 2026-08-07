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
| `expanded-scroll` | `endless` \| `rewind` | `endless` |
| `haptics` | `never` \| `open` \| `peek` \| `all` | `never` |
| `haptic-pattern` | `generic` \| `alignment` \| `level-change` | `alignment` |

`open-on = never` leaves the notch inert to the pointer; widgets can still peek.

`open-delay` is how long the pointer must rest on the notch before it opens, which stops it flying
open every time you cross the top of the screen on the way to the menu bar. Ignored unless
`open-on` is `hover`. Durations are written `120ms`, `1.5s`, or a bare number read as milliseconds.

Clicking toggles the panel even when `open-on` is `hover`, so there is always a way to dismiss it
without moving the pointer off it.

#### Scrolling between widgets

The open panel shows one widget at a time. Scrolling vertically over it moves to the next, one per
swipe however hard the swipe is thrown — a panel this small showing four widgets go past on one
flick is a panel you have to scroll back through.

`expanded-scroll` is what happens at the ends of the list.

```ini
expanded-scroll = rewind
```

`endless`, the default, has no ends: scrolling down past the last widget carries on downwards into
the first, and up past the first carries on up into the last. Nothing ever turns round.

`rewind` treats the list as having a top and a bottom, and going past either sweeps back to the
other. The movement is visibly a return rather than a continuation, which is the point of choosing
it — with two or three widgets it can be easier to keep your place when the panel tells you you
have been all the way round.

Neither refuses to scroll. Being stopped dead at an end reads as broken rather than as an end,
because a panel showing one widget at a time has nothing on screen to say there is an end there.

A wheel mouse turns one widget per few detents rather than per gesture, since it emits no gesture
to latch onto.

#### Haptics

`haptics` taps the trackpad when the notch changes state. Two things can tap, and the four values
cover every combination: `open` when the notch opens, `peek` when a widget announces something,
`all` for both, `never` for neither.

```ini
haptics        = all
haptic-pattern = level-change
```

Only transitions *into* an open or announcing state tap. Collapsing does not — by the time the
notch closes the pointer has already left it, and a tap chasing you away tells you nothing you did
not just do on purpose.

Scrolling from one widget to the next taps too, whenever haptics are on at all — `open` and `peek`
do not gate it. Those two are about being notified, which is a taste; a widget turning under your
own fingers is feedback for a movement you are in the middle of making, and it always uses
`level-change` whatever `haptic-pattern` says, because that is the detent it is imitating.

`haptic-pattern` picks how the tap feels, from the three patterns macOS ships: `alignment` is the
light tap of something snapping to a guide, `generic` a single firmer one, and `level-change` the
two-part tap of a detent moving between stops. These name system patterns rather than an intensity
because macOS tunes each one to the hardware and to the trackpad settings, which a hand-rolled
intensity would fight.

**It is off by default,** which is a deliberate choice rather than an oversight. The notch opens on
hover, so every trip to the menu bar passes over it — a tap on each of those is something you feel
all day without having asked for it. Turning it on is a small, specific "yes I want this".

**It needs the hardware.** Haptic feedback does nothing on a Mac without a Force Touch trackpad —
an external mouse, an older machine, a Mac mini — and nothing when *Force Click and haptic
feedback* is switched off in System Settings. perch does not work around either: a machine that
cannot tap simply does not, and a user who turned haptics off system-wide meant it.

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

**Only the widget with something to announce appears in one**, whatever else you have configured
into the panel. A track change is media's announcement; a scratchpad or a clock arriving alongside
it is not announcing anything, and a peek is too short to read two things anyway. Widgets opt into
peeks the same way they opt into running while hidden — by having something to say.

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
| `expanded-height` | points | `94` |
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
all. Everything else is opt-in, and declaring one adds to that default rather than replacing it —
`widget = notes` on its own gives you media *and* notes. Use `widget =` first if you want to start
from nothing.

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

The panel is one horizontal band: artwork on the left, and beside it the track, the transport
controls at the right edge, and a scrubber with the elapsed time and the length flanking it. Laid
out sideways rather than stacked because the panel hangs off the notch and is much wider than it is
tall — height is the axis worth spending carefully, which is why the times sit beside the bar
instead of under it.

Dragging or clicking the scrubber seeks, and the bar follows your pointer rather than the player,
since the player reports nothing until you let go. A track whose length the player does not
report — live streams, most browser audio — gets no scrubber at all rather than a bar that cannot
say where it is.

Lower `expanded-height` much below its default and the scrubber is the first thing to run out of
room.

Unlike most widgets, media keeps working while the notch is closed. It has to: a track change
cannot be announced by something that is not watching, and opening the notch should show the
current track rather than an empty panel. The helper it runs idles at 0% CPU and about 18MB, and
is released if the notch stays shut for 90 seconds.

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

### notes

A scratchpad in the expanded panel. Opt-in: it is a place to *put* things, and a widget that keeps
what you type has to be asked for rather than found.

| Key | Accepts | Default |
|---|---|---|
| `notes-placement` | `expanded` | `expanded` |
| `notes-placeholder` | text | `Jot something down…` |

```ini
widget = notes
notes-placeholder = Later.
```

The note is a plain `notes.txt` beside your config, written a moment after you stop typing rather
than on every keystroke, and re-read each time the panel opens — so editing the file in a real
editor works, and does not lose whatever the panel had. Only `expanded` is a meaningful placement;
the collapsed strip has no room to type.

## Only one perch

perch takes an exclusive lock on `perch.lock` in its config directory at startup. A second copy
prints which process holds it and exits rather than drawing a second panel over the same notch.
The lock is held by the kernel, so it is released even if perch crashes — there is no stale lock
to clear.

## Displays without a notch

perch works on external monitors. When a display reports no camera housing it gets a synthetic
pill hanging from the top edge instead, and every setting above applies to it unchanged.
