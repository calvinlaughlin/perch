import AppKit
import PerchCore
import SwiftUI

/// A scrollable scratchpad for quick notes.
///
/// Sits beside media in the expanded panel and persists to `notes.txt` in the config directory,
/// with debounced writes so the file is not rewritten on every keystroke. Only the notes' own
/// content scrolls — the panel itself never resizes.
@MainActor
@Observable
public final class NotesWidget: NotchWidget {

    public static let kind = "notes"

    public static let summary = "A scrollable scratchpad for quick notes."

    public static let settings: [WidgetSetting] = [
        WidgetSetting(
            name: "placement", syntax: "expanded", defaultValue: "expanded",
            documentation:
                "Where the widget draws. Only `expanded` is meaningful — the strip has no room to type."
        ),
        WidgetSetting(
            name: "placeholder", syntax: "text", defaultValue: "Jot something down…",
            documentation: "Text shown when the note is empty."),
    ]

    public let placement: Placement

    private let placeholder: String
    private let store: NotesStore

    fileprivate var text: String = ""

    public init(settings: WidgetSettings) throws {
        placement = try settings.enumeration("placement", default: .expanded)
        placeholder = settings.string("placeholder", default: "Jot something down…")
        store = NotesStore()
    }

    public func activate() {
        // Load once whenever the panel opens. The store is the source of truth on disk; the widget
        // is a live editor over the top of it. Between opens the user could have edited the file
        // externally, and re-reading here means that shows up on the next open rather than being
        // silently overwritten.
        Task { [weak self] in
            guard let self else { return }
            let contents = await self.store.load()
            self.text = contents
        }
    }

    public func deactivate() {
        // Force any pending debounced write to disk. If we skipped this, closing the notch within
        // the debounce window after a keystroke would lose that keystroke.
        Task { [store] in await store.flush() }
    }

    public var body: AnyView {
        AnyView(NotesWidgetView(widget: self, placeholder: placeholder))
    }

    fileprivate func edited(to newText: String) {
        text = newText
        Task { [store] in await store.update(newText) }
    }
}

private struct NotesWidgetView: View {

    @Bindable var widget: NotesWidget
    let placeholder: String

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if widget.text.isEmpty && !isFocused {
                Text(placeholder)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("notes.placeholder")
            }

            editor
        }
        .accessibilityIdentifier("notes.container")
    }

    private var editor: some View {
        TextEditor(
            text: Binding(
                get: { widget.text },
                set: { widget.edited(to: $0) }
            )
        )
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.9))
        .tint(.white)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .focused($isFocused)
        .accessibilityIdentifier("notes.editor")
    }
}
