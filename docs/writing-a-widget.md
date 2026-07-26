# Writing a widget

A widget is one file. It declares a name, reads its own settings, says where it draws, and starts
and stops its own work.

```swift
import PerchCore
import SwiftUI

@MainActor
final class ClockWidget: NotchWidget {
    static let kind = "clock"

    let placement: Placement
    private let showsSeconds: Bool
    private var ticker: Task<Void, Never>?

    private var now = Date()

    init(settings: WidgetSettings) throws {
        placement = try settings.enumeration("placement", default: .trailing)
        showsSeconds = try settings.bool("seconds", default: false)
    }

    func activate() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run { self?.now = Date() }
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

Register it once, in `AppDelegate`:

```swift
WidgetRegistry.shared.register(ClockWidget.self)
```

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

## Testing

Widget logic that does not need a screen belongs in `PerchCore` and is tested there. For the
widget itself, `Tests/PerchUITests/WidgetHostTests.swift` shows the pattern — a spy widget that
counts activations, which is how the lifecycle guarantees above are verified.
