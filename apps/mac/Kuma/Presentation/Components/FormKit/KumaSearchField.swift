import SwiftUI
import AppKit

// MARK: - Native NSSearchField Representable

/// Wraps native AppKit `NSSearchField` for 100% pixel-perfect macOS search capsule styling anywhere in views/sheets.
@MainActor
public struct KumaSearchField: NSViewRepresentable {
    @Binding public var text: String
    public var prompt: String

    public init(text: Binding<String>, prompt: String = "Search services…") {
        self._text = text
        self.prompt = prompt
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    public func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = prompt
        searchField.stringValue = text
        searchField.delegate = context.coordinator
        searchField.focusRingType = .default
        searchField.controlSize = .small
        searchField.font = .systemFont(ofSize: 12)
        searchField.bezelStyle = .roundedBezel
        return searchField
    }

    public func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = prompt
    }

    @MainActor
    public class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        public func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSSearchField {
                self.text.wrappedValue = field.stringValue
            }
        }
    }
}

