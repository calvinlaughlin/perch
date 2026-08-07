import PerchCore
import Testing

@testable import PerchUI

/// Settings the media widget parses for itself.
///
/// These assert that a key is *read*, not merely documented: a widget can list a setting in
/// `settings` and then never look at it, and the generated config would still advertise it.
/// Rejecting a bad value is only possible if something parsed it.
@MainActor
struct MediaWidgetTests {

    private func widget(_ values: [String: String]) throws -> MediaWidget {
        try MediaWidget(settings: WidgetSettings(kind: "media", values: values))
    }

    @Test("media-text is parsed rather than ignored")
    func textSettingIsParsed() throws {
        let error = try #require(throws: ConfigValueError.self) {
            _ = try widget(["text": "perhaps"])
        }

        // Named as the user spelled it in the file, not as the bare setting.
        #expect(error.message.contains("media-text"))
    }

    @Test("media-text accepts both values and defaults to on")
    func textSettingAcceptsBooleans() throws {
        #expect(throws: Never.self) { _ = try widget(["text": "false"]) }
        #expect(throws: Never.self) { _ = try widget(["text": "true"]) }
        #expect(throws: Never.self) { _ = try widget([:]) }

        let documented = MediaWidget.settings.first { $0.name == "text" }
        #expect(documented?.defaultValue == "true")
    }
}
