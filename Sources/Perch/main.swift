import AppKit
import PerchCore
import PerchUI

// Unbuffer stdout. perch is normally launched from a terminal during development (`make run`),
// and block buffering would hold log lines hostage until the buffer filled or the app exited —
// which for a long-running ambient app means never.
setvbuf(stdout, nil, _IONBF, 0)

// A few actions that answer a question and exit, rather than starting the app. They are spelled
// `+show-config` rather than `--show-config` to keep the two kinds of argument visibly apart: a
// `+action` chooses what perch does instead of running, a `--flag` modifies it. Without that split
// `--docs` reads like it belongs to the app rather than to one action.
//
// `+show-config` in particular is generated from the same table the parser uses, so it is a
// reference that cannot go stale — and its output is itself a valid config file. It carries the
// weight the config file used to: the file perch writes is a few lines long and points here.
//
// Before the actions, not after: `+show-config` and `+edit-config` both need the registered
// widgets to exist, since they document them.
WidgetRegistry.registerBuiltIns()

let arguments = Array(CommandLine.arguments.dropFirst())
let flags = Set(arguments.filter { $0.hasPrefix("-") })

/// The chosen `+action`, if any.
///
/// Anything else starting with `+` is a mistake worth naming rather than ignoring — silently
/// launching the app is a confusing answer to a typo.
let action = arguments.first { $0.hasPrefix("+") }

// `--help` and `--version` work as flags too. They are what someone types before knowing a tool
// has actions at all, and `perch --version` is what the release smoke test asks.
let wantsHelp = action == "+help" || flags.contains("--help") || flags.contains("-h")
let wantsVersion = action == "+version" || flags.contains("--version")

if wantsHelp {
    print(
        """
        perch — a minimal, config-driven macOS notch app

        usage: perch [+action] [options]

        actions:
          +show-config      print the config and exit
          +edit-config      open the config file, creating it if needed
          +config-path      print where perch looks for its config file
          +version          print the version
          +help             print this message

        options for +show-config:
          --default         print perch's defaults rather than the active config
          --docs            document each key, and list every widget

        With no action, perch runs.

        Config lives at \(ConfigPaths.display(ConfigPaths.configFile)) and is reloaded when saved.
        Right-click the notch for the same actions without a terminal.
        """
    )
    exit(0)
}

if wantsVersion {
    print("perch \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
    exit(0)
}

if action == "+edit-config" {
    // Same code path as the notch menu, so the two cannot drift apart.
    let file = ConfigPaths.ensureConfigFileExists(contents: ConfigTemplate.starter())
    print(ConfigPaths.display(file))
    let editor = Process()
    editor.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    editor.arguments = [file.path]
    try? editor.run()
    editor.waitUntilExit()
    exit(0)
}

if action == "+config-path" {
    print(ConfigPaths.configFile.path)
    exit(0)
}

if action == "+show-config" {
    let includeDocs = flags.contains("--docs")

    // `--default` answers "what would perch do with no config at all?", which is the question you
    // have while writing one. Reading the file to answer it would defeat the point, so it doesn't.
    if flags.contains("--default") {
        print(ConfigTemplate.reference(Config(), includeDocs: includeDocs))
        exit(0)
    }

    let result = ConfigLoader.load(contentsOf: ConfigPaths.configFile)
    for diagnostic in result.diagnostics {
        FileHandle.standardError.write(Data("\(diagnostic.description)\n".utf8))
    }
    print(ConfigTemplate.reference(result.config, includeDocs: includeDocs))
    exit(result.diagnostics.isEmpty ? 0 : 1)
}

if let action {
    FileHandle.standardError.write(
        Data("perch: unknown action '\(action)' — try 'perch +help'\n".utf8))
    exit(1)
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
