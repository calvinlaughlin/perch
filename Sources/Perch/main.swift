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
          --edit-config     open the config file, creating it if needed
          --config-path     print where perch looks for its config file
          --version         print the version
          -h, --help        print this message

        Config lives at \(ConfigPaths.display(ConfigPaths.configFile)) and is reloaded when saved.
        Right-click the notch for the same actions without a terminal.
        """
    )
    exit(0)
}

if arguments.contains("--version") {
    print("perch \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
    exit(0)
}

if arguments.contains("--edit-config") {
    // Same code path as the notch menu, so the two cannot drift apart.
    let file = ConfigPaths.ensureConfigFileExists()
    print(ConfigPaths.display(file))
    let editor = Process()
    editor.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    editor.arguments = [file.path]
    try? editor.run()
    editor.waitUntilExit()
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

// Only one perch. Two would draw two panels over the same notch, both react to the same hover,
// and each would reap the other's media helper.
guard let instanceLock = SingleInstanceLock() else {
    let holder = SingleInstanceLock.holder().map { " (pid \($0))" } ?? ""
    FileHandle.standardError.write(
        Data("perch: another instance is already running\(holder)\n".utf8))
    exit(1)
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

// Keeps the lock alive for the whole run; without this the compiler is free to release it early.
withExtendedLifetime(instanceLock) {}
