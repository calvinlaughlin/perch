# Writing a widget

A widget is one file. It declares a name, reads its own settings, says where it draws, and starts
and stops its own work.

```swift
import PerchCore
import SwiftUI

@MainActor
@Observable
final class ClockWidget: NotchWidget {
    static let kind = "clock"

    // Shown in the starter config perch writes on first run.
    static let summary = "Shows the time."
    static let settings: [WidgetSetting] = [
        WidgetSetting(
            name: "seconds", syntax: "true | false", defaultValue: "false",
            documentation: "Include seconds.")
    ]

    let placement: Placement
    private let showsSeconds: Bool
    private var ticker: Task<Void, Never>?

    fileprivate private(set) var now = Date()

    init(settings: WidgetSettings) throws {
        placement = try settings.enumeration("placement", default: .trailing)
        showsSeconds = try settings.bool("seconds", default: false)
    }

    func activate() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.now = Date()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func deactivate() {
        ticker?.cancel()
        ticker = nil
    }

    var body: AnyView {
        AnyView(Text(now, format: .dateTime.hour().minute()).foregroundStyle(.white))
    }
}
```

Register it in `WidgetRegistry.registerBuiltIns()`:

```swift
shared.register(ClockWidget.self)
```

Registration lives there rather than in `AppDelegate` because `perch --edit-config` generates a
starter config listing the available widgets, and it runs before the app starts.

It is now reachable from config:

```ini
widget = clock
clock-placement = trailing
clock-seconds   = true
```

## The name

`NotchWidget`, not `Widget` — SwiftUI already declares a `Widget` protocol for WidgetKit
extensions, and since every widget file imports SwiftUI, using the obvious name makes every one of
them ambiguous.

## Settings

`static let kind` is both the name in `widget = clock` and the prefix for that widget's settings.
`clock-seconds` arrives as the setting `seconds`.

Settings are parsed by the widget, not by the config schema, which is why adding a widget needs no
change to `Config`. `WidgetSettings` has typed accessors — `bool`, `length`, `duration`,
`enumeration`, `string` — and every one takes a default:

```swift
showsSeconds = try settings.bool("seconds", default: false)
```

**A widget must work with no settings at all.** The defaults you pass here are what someone gets
from a bare `widget = clock`, and that has to be a state worth shipping.

Throwing from `init` is fine and expected for a value that cannot be parsed. It surfaces as an
ordinary config diagnostic naming the key as the user spelled it, and the other widgets still
load.

`summary` and `settings` are optional but worth filling in: they are what makes the widget appear,
documented, in the config perch writes on first run. Without them the only way to discover the
widget is to read the source.

## Placement

| Placement | Where | Visible |
|---|---|---|
| `leading` | strip left of the camera housing | always |
| `trailing` | strip right of the camera housing | always |
| `expanded` | body of the open panel | only when open |

The collapsed strips only have room when `collapsed-bleed` is non-zero — at zero the collapsed
shape traces the housing exactly, and anything drawn there is behind opaque hardware.

## activate / deactivate

**This is the part that matters.** `activate()` is called when the widget becomes visible;
`deactivate()` when it stops being visible — the notch closing, the display sleeping, config
reloading.

`deactivate()` must release **everything**: timers, tasks, observers, notification registrations,
subprocesses. perch's claim to cost nothing while idle is exactly the sum of every widget honouring
this, and one widget that leaks a timer quietly undoes it for the whole app.

An `expanded` widget is not activated at all while the notch is collapsed, so work that only makes
sense when someone is looking never starts.

The host guarantees these are balanced: no double `activate()`, and `deactivate()` only after a
matching `activate()`.

### Running while hidden

A widget that needs to keep working when it cannot be seen opts in:

```swift
var runsWhileHidden: Bool { true }
```

`false` by default, and that default is the point. Opting in is a promise that idle cost is
genuinely negligible — **measure it before making that promise.** The media widget opts in because
a track change cannot be announced by something that is not watching; its helper measures 0% CPU
and about 18MB.

## Announcing something

A widget can ask the notch to peek — briefly enlarge to show something, then revert. Take the
handle when it is offered:

```swift
private var attention: (any NotchAttention)?

func attach(attention: any NotchAttention) {
    self.attention = attention
}
```

and ask when something worth announcing happens:

```swift
attention?.requestPeek(from: self)
```

Whether the request is honoured is not the widget's decision: a peek never interrupts a panel the
user opened themselves, and it reverts on its own after `peek-duration`.

Passing `self` is what lets the notch show *your* `peekBody`, whatever your `placement`. A widget
that lives in the collapsed strip has room for a dot and not much else, so being able to say more
than a strip is wide enough to hold is the point of announcing at all.

Peeks are for genuine changes, not for updates. The media widget peeks on a change of *track*, not
on every playback update — announcing each one would be intolerable.

`peekBody` is what your widget draws in one, and it is `nil` by default — a widget that has never
announced anything has nothing to say in the two seconds a peek lasts, and appearing there
regardless means someone else's track change hands the user your scratchpad. Override it only if
you also call `requestPeek`, and return a compact form: a peek is glanced at, not read.

```swift
var peekBody: AnyView? { AnyView(Text(title).font(.system(size: 12))) }
```

## Testing

Widget logic that does not need a screen belongs in `PerchCore` and is tested there. For the
widget itself, `Tests/PerchUITests/WidgetHostTests.swift` shows the pattern — a spy widget that
counts activations, which is how the lifecycle guarantees above are verified.
