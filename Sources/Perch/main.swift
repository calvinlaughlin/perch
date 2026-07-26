import AppKit
import PerchCore
import PerchUI

// Unbuffer stdout. perch is normally launched from a terminal during development (`make run`),
// and block buffering would hold log lines hostage until the buffer filled or the app exited —
// which for a long-running ambient app means never.
setvbuf(stdout, nil, _IONBF, 0)

// A few flags that answer a question and exit, rather than starting the app. `--show-config` in
// particular is generated from the same table the parser uses, so it is a reference that cannot go
// stale — and its output is itself a valid config file.
let arguments = Set(CommandLine.arguments.dropFirst())

if arguments.contains("--help") || arguments.contains("-h") {
    print(
        """
        perch — a minimal, config-driven macOS notch app

        usage: perch [options]

          --show-config     print the active config and exit
          --docs            include documentation in --show-config output
          --config-path     print where perch looks for its config file
          --version         print the version
          -h, --help        print this message

        Config lives at \(ConfigPaths.display(ConfigPaths.configFile)) and is reloaded when saved.
        """
    )
    exit(0)
}

if arguments.contains("--version") {
    print("perch \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
    exit(0)
}

if arguments.contains("--config-path") {
    print(ConfigPaths.configFile.path)
    exit(0)
}

if arguments.contains("--show-config") {
    let result = ConfigLoader.load(contentsOf: ConfigPaths.configFile)
    for diagnostic in result.diagnostics {
        FileHandle.standardError.write(Data("\(diagnostic.description)\n".utf8))
    }
    print(ConfigSchema.show(result.config, includeDocs: arguments.contains("--docs")))
    exit(result.diagnostics.isEmpty ? 0 : 1)
}

// perch has no windows of its own in the ordinary sense and no dock presence, so it drives
// NSApplication directly rather than going through the SwiftUI `App` lifecycle. That lifecycle
// wants to own window creation, which is exactly the part we need control over.

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate

// `.accessory`: no dock icon, no menu bar, never becomes the active app.
application.setActivationPolicy(.accessory)

application.run()
