import AppKit
import PerchUI

// perch has no windows of its own in the ordinary sense and no dock presence, so it drives
// NSApplication directly rather than going through the SwiftUI `App` lifecycle. That lifecycle
// wants to own window creation, which is exactly the part we need control over.

// Unbuffer stdout. perch is normally launched from a terminal during development (`make run`),
// and block buffering would hold log lines hostage until the buffer filled or the app exited —
// which for a long-running ambient app means never.
setvbuf(stdout, nil, _IONBF, 0)

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate

// `.accessory`: no dock icon, no menu bar, never becomes the active app.
application.setActivationPolicy(.accessory)

application.run()
