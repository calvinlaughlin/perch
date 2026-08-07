import PerchCore
import Testing

@testable import PerchUI

/// What perch actually builds with no config file.
///
/// `Config.widgets` is an array literal; this is the other half — that the literal survives the
/// registry and becomes the set of widgets that reach the panel. A default nobody constructs is
/// not a default.
@MainActor
struct DefaultWidgetsTests {

    /// The shipped widgets, on a private registry so tests never mutate the shared one.
    private func registry() -> WidgetRegistry {
        let registry = WidgetRegistry()
        registry.register(MediaWidget.self)
        registry.register(ClockWidget.self)
        registry.register(NotesWidget.self)
        return registry
    }

    @Test("No config file builds media and nothing else")
    func defaultBuildsMediaAlone() {
        let (widgets, diagnostics) = registry().makeAll(for: Config())

        #expect(widgets.contains { $0 is MediaWidget })
        // A widget that keeps what you type must be asked for: nobody should be writing to a
        // scratchpad they never opted into.
        #expect(!widgets.contains { $0 is NotesWidget })
        #expect(widgets.count == 1)
        #expect(diagnostics.isEmpty)
    }

    @Test("Declaring notes builds it without losing the default")
    func notesIsBuiltWhenDeclared() {
        let config = ConfigLoader.load(source: "widget = notes").config
        let (widgets, diagnostics) = registry().makeAll(for: config)

        #expect(widgets.contains { $0 is NotesWidget })
        #expect(widgets.contains { $0 is MediaWidget })
        #expect(diagnostics.isEmpty)
    }

    @Test("The starter config offers notes as something to turn on")
    func starterConfigOffersNotes() {
        let text = ConfigTemplate.starter(registry: registry())

        // Opt-in is only fair if it is discoverable, and the generated file is where someone finds
        // out notes exists at all — it is the one place perch volunteers the list.
        #expect(text.contains("#widget = notes"))
        #expect(!text.contains("\nwidget = notes"))
        #expect(text.contains("\nwidget = media"))
    }

    @Test("Notes settings still route once it is declared")
    func notesSettingsRoute() {
        let config = ConfigLoader.load(
            source: """
                widget = notes
                notes-placeholder = Later.
                """
        ).config

        #expect(config.settings(for: "notes").string("placeholder", default: "") == "Later.")
    }
}
