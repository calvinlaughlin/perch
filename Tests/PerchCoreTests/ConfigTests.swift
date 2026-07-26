import CoreGraphics
import Foundation
import Testing

@testable import PerchCore

@Suite("Config syntax")
struct ConfigParserTests {
    @Test("A key and value are separated on the equals sign")
    func parsesAssignment() {
        let (assignments, diagnostics) = ConfigParser.parse("open-on = click")

        #expect(diagnostics.isEmpty)
        #expect(assignments == [ConfigAssignment(key: "open-on", value: "click", line: 1)])
    }

    @Test("Whitespace around the equals sign is irrelevant")
    func whitespaceIsIrrelevant() {
        let (spaced, _) = ConfigParser.parse("  open-on   =   click  ")
        let (tight, _) = ConfigParser.parse("open-on=click")

        #expect(spaced.first?.value == "click")
        #expect(tight.first?.value == "click")
    }

    @Test("Comments and blank lines are ignored")
    func ignoresCommentsAndBlanks() {
        let source = """
            # a comment

            open-on = click
              # an indented comment
            """
        let (assignments, diagnostics) = ConfigParser.parse(source)

        #expect(diagnostics.isEmpty)
        #expect(assignments.count == 1)
    }

    @Test("Values may be quoted to preserve spacing or a literal hash")
    func stripsQuotes() {
        let (assignments, _) = ConfigParser.parse(#"key = "a value # here""#)

        #expect(assignments.first?.value == "a value # here")
    }

    @Test("An empty value marks the key for reset")
    func emptyValueIsAReset() {
        let (assignments, _) = ConfigParser.parse("open-on =")

        #expect(assignments.first?.isReset == true)
    }

    @Test("Line numbers survive comments and blanks, so diagnostics point at the right line")
    func reportsAccurateLineNumbers() {
        let source = """
            # comment

            open-on = click
            nonsense
            """
        let (_, diagnostics) = ConfigParser.parse(source)

        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.line == 4)
    }

    @Test("A line with no equals sign is reported and skipped")
    func reportsMissingSeparator() {
        let (assignments, diagnostics) = ConfigParser.parse("open-on click\nopen-delay = 50ms")

        #expect(assignments.count == 1)  // the good line still applies
        #expect(diagnostics.first?.severity == .warning)
    }

    @Test("A line with no key is reported")
    func reportsMissingKey() {
        let (assignments, diagnostics) = ConfigParser.parse("= click")

        #expect(assignments.isEmpty)
        #expect(diagnostics.count == 1)
    }
}

@Suite("Config values")
struct ConfigValueTests {
    @Test("Booleans accept the spellings people actually use")
    func parsesBooleanSpellings() throws {
        for text in ["true", "yes", "on", "1", "TRUE"] {
            #expect(try ConfigValue.bool(text))
        }
        for text in ["false", "no", "off", "0"] {
            #expect(try !ConfigValue.bool(text))
        }
    }

    @Test("Durations accept milliseconds, seconds, and a bare number")
    func parsesDurations() throws {
        #expect(try ConfigValue.duration("120ms") == .milliseconds(120))
        #expect(try ConfigValue.duration("1.5s") == .milliseconds(1500))
        #expect(try ConfigValue.duration("200") == .milliseconds(200))
    }

    @Test("A negative length is rejected")
    func rejectsNegativeLength() {
        #expect(throws: ConfigValueError.self) { try ConfigValue.length("-10") }
    }

    @Test("An unparseable value explains what was expected")
    func explainsWhatWasExpected() throws {
        let error = try #require(throws: ConfigValueError.self) {
            try ConfigValue.enumeration("sideways", as: OpenTrigger.self)
        }

        // The reader is editing a text file, so the message has to list the options.
        #expect(error.message.contains("hover"))
        #expect(error.message.contains("click"))
        #expect(error.message.contains("never"))
    }

    @Test("Durations round-trip through their written form")
    func durationsRoundTrip() throws {
        let written = ConfigValue.describe(.milliseconds(250))

        #expect(written == "250ms")
        #expect(try ConfigValue.duration(written) == .milliseconds(250))
    }
}

@Suite("Config loading")
struct ConfigLoaderTests {
    @Test("An empty config is the default config")
    func emptyConfigIsDefaults() {
        let result = ConfigLoader.load(source: "")

        #expect(result.config == Config())
        #expect(result.diagnostics.isEmpty)
    }

    @Test("Settings are applied")
    func appliesSettings() {
        let result = ConfigLoader.load(
            source: """
                open-on = click
                open-delay = 300ms
                expanded-height = 240
                debug-shape = true
                """
        )

        #expect(result.config.openOn == .click)
        #expect(result.config.openDelay == .milliseconds(300))
        #expect(result.config.expandedHeight == 240)
        #expect(result.config.debugShape)
        #expect(result.diagnostics.isEmpty)
    }

    @Test("A later assignment wins")
    func laterAssignmentWins() {
        let result = ConfigLoader.load(source: "open-on = click\nopen-on = never")

        #expect(result.config.openOn == .never)
    }

    @Test("An empty value restores the default")
    func emptyValueRestoresDefault() {
        let result = ConfigLoader.load(source: "open-on = never\nopen-on =")

        #expect(result.config.openOn == Config().openOn)
    }

    @Test("A bad value is skipped and everything else still applies")
    func badValueDoesNotPoisonTheFile() {
        // This is the behaviour that makes the file safe to edit while perch is running.
        let result = ConfigLoader.load(
            source: """
                open-on = sideways
                expanded-height = 240
                """
        )

        #expect(result.config.openOn == Config().openOn)  // untouched
        #expect(result.config.expandedHeight == 240)  // still applied
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics.first?.line == 1)
    }

    @Test("An unknown key is a warning, not a failure")
    func unknownKeyIsAWarning() {
        let result = ConfigLoader.load(source: "wibble = 3\nexpanded-height = 240")

        #expect(result.config.expandedHeight == 240)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics.first?.severity == .warning)
    }

    @Test("A near-miss key suggests the real one")
    func suggestsNearMisses() {
        // Keys are hyphenated and typed from memory, so near-misses are the common failure.
        let result = ConfigLoader.load(source: "open_on = click")

        #expect(result.diagnostics.first?.message.contains("open-on") == true)
    }

    @Test("A wildly wrong key does not invent a suggestion")
    func doesNotInventSuggestions() {
        let result = ConfigLoader.load(source: "xyzzy = 1")

        #expect(result.diagnostics.first?.message.contains("did you mean") == false)
    }

    @Test("Diagnostics read like compiler output")
    func diagnosticsAreConventional() {
        let result = ConfigLoader.load(source: "open-on = sideways", file: "/tmp/config")

        #expect(result.diagnostics.first?.description.hasPrefix("/tmp/config:1: warning:") == true)
    }

    @Test("A missing file is not an error")
    func missingFileIsFine() {
        // perch is meant to be good with no config at all, so absence cannot be a problem.
        let url = URL(fileURLWithPath: "/nonexistent/perch/config")
        let result = ConfigLoader.load(contentsOf: url)

        #expect(result.config == Config())
        #expect(result.diagnostics.isEmpty)
    }

    @Test("Total garbage still yields a usable config")
    func garbageStillLoads() {
        let result = ConfigLoader.load(
            source: """
                !!!! ???
                = = =
                open-on
                \u{0}
                """
        )

        #expect(result.config == Config())
        #expect(!result.diagnostics.isEmpty)
    }
}

@Suite("Config schema")
struct ConfigSchemaTests {
    @Test("Every key is documented and has a syntax hint")
    func everyKeyIsDocumented() {
        for key in ConfigSchema.keys {
            #expect(!key.documentation.isEmpty, "\(key.name) has no documentation")
            #expect(!key.syntax.isEmpty, "\(key.name) has no syntax hint")
        }
    }

    @Test("Key names are unique and hyphenated")
    func keyNamesAreWellFormed() {
        var seen = Set<String>()
        for key in ConfigSchema.keys {
            #expect(seen.insert(key.name).inserted, "\(key.name) is defined twice")
            #expect(key.name == key.name.lowercased(), "\(key.name) is not lowercase")
            #expect(!key.name.contains("_"), "\(key.name) uses an underscore, not a hyphen")
        }
    }

    @Test("Generated defaults parse back to the defaults")
    func generatedDefaultsRoundTrip() {
        // `--show-config` output has to be a valid config file, or it is a lie rather than a
        // reference. This also proves no key's `describe` has drifted from its parser.
        let result = ConfigLoader.load(source: ConfigSchema.show())

        #expect(result.diagnostics.isEmpty)
        #expect(result.config == Config())
    }

    @Test("Generated output with docs also parses back")
    func documentedOutputRoundTrips() {
        let result = ConfigLoader.load(source: ConfigSchema.show(includeDocs: true))

        #expect(result.diagnostics.isEmpty)
        #expect(result.config == Config())
    }

    @Test("A non-default config round-trips through its written form")
    func modifiedConfigRoundTrips() {
        var config = Config()
        config.openOn = .never
        config.openDelay = .milliseconds(75)
        config.expandedHeight = 321
        config.debugShape = true

        let result = ConfigLoader.load(source: ConfigSchema.show(config))

        #expect(result.diagnostics.isEmpty)
        #expect(result.config == config)
    }
}

@Suite("Widget configuration")
struct WidgetConfigTests {
    @Test("Repeating the widget key builds a list in declaration order")
    func widgetsAreListed() {
        let result = ConfigLoader.load(source: "widget =\nwidget = media\nwidget = clock")

        #expect(result.config.widgets == ["media", "clock"])
        #expect(result.diagnostics.isEmpty)
    }

    @Test("Declaring the same widget twice does not duplicate it")
    func widgetsAreDeduplicated() {
        let result = ConfigLoader.load(source: "widget = media\nwidget = media")

        #expect(result.config.widgets == ["media"])
    }

    @Test("An empty widget key clears the list")
    func emptyWidgetKeyClearsTheList() {
        // Lets a pasted block start from nothing without knowing what came above it.
        let result = ConfigLoader.load(source: "widget = media\nwidget =\nwidget = clock")

        #expect(result.config.widgets == ["clock"])
    }

    @Test("Prefixed keys route to their widget")
    func settingsRouteToTheirWidget() {
        let result = ConfigLoader.load(
            source: """
                widget = media
                media-artwork = true
                media-placement = expanded
                """
        )

        let settings = result.config.settings(for: "media")
        #expect(try! settings.bool("artwork", default: false))
        #expect(settings.string("placement", default: "") == "expanded")
        #expect(result.diagnostics.isEmpty)
    }

    @Test("Settings may appear above the widget that owns them")
    func settingsMayPrecedeTheirDeclaration() {
        // People group settings by topic, not by declaration order.
        let result = ConfigLoader.load(source: "media-artwork = true\nwidget = media")

        #expect(try! result.config.settings(for: "media").bool("artwork", default: false))
        #expect(result.diagnostics.isEmpty)
    }

    @Test("A prefixed key with no declared widget says what is missing")
    func undeclaredWidgetSettingIsExplained() {
        let result = ConfigLoader.load(source: "clock-format = 24h")

        let message = result.diagnostics.first?.message ?? ""
        #expect(message.contains("widget = clock"))
    }

    @Test("The media widget is on by default")
    func mediaIsOnByDefault() {
        // Zero configuration has to be worth shipping, and a notch showing nothing is not.
        #expect(Config().widgets == ["media"])
        #expect(ConfigLoader.load(source: "").config.widgets == ["media"])
    }

    @Test("Declaring widgets replaces nothing implicitly")
    func defaultSurvivesUnrelatedSettings() {
        let result = ConfigLoader.load(source: "open-on = click")

        #expect(result.config.widgets == ["media"])
    }

    @Test("The longest matching widget prefix wins")
    func longestPrefixWins() {
        let result = ConfigLoader.load(
            source: """
                widget = media
                widget = media-remote
                media-remote-timeout = 5s
                """
        )

        #expect(result.config.settings(for: "media-remote").names == ["timeout"])
        #expect(result.config.settings(for: "media").names.isEmpty)
    }

    @Test("A widget's settings survive a round trip through a bad value")
    func badWidgetValueIsReportedByTheWidget() throws {
        // Core stores settings as written; the widget parses them, so the error names the key as
        // the user spelled it rather than the bare setting.
        let result = ConfigLoader.load(source: "widget = media\nmedia-artwork = perhaps")
        let settings = result.config.settings(for: "media")

        let error = try #require(throws: ConfigValueError.self) {
            try settings.bool("artwork", default: false)
        }
        #expect(error.message.contains("media-artwork"))
    }

    @Test("A widget with no settings still yields usable defaults")
    func widgetsWorkWithNoSettings() throws {
        let result = ConfigLoader.load(source: "widget = media")
        let settings = result.config.settings(for: "media")

        #expect(try settings.bool("artwork", default: true))
        #expect(settings.string("placement", default: "expanded") == "expanded")
    }

    @Test("Core keys are not mistaken for widget settings")
    func coreKeysStillWork() {
        // `open-on` must not be read as widget `open`, setting `on`.
        let result = ConfigLoader.load(source: "widget = open\nopen-on = click")

        #expect(result.config.openOn == Config().openOn)  // routed to the widget, not the core key
        #expect(result.config.settings(for: "open").names == ["on"])
    }
}
