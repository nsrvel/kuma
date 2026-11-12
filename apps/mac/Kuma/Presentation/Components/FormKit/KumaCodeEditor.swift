import SwiftUI
import AppKit

// MARK: - Shared code editor typography (NSTextView + SwiftUI placeholder)

public enum KumaCodeEditorStyle {
    public static let fontSize: CGFloat = 11.5
    public static let textInset: CGFloat = 6

    public static var swiftUIFont: Font {
        .system(size: fontSize, weight: .regular, design: .monospaced)
    }

    public static var nsFont: NSFont {
        .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }
}

// MARK: - KumaCodeEditor

/// Professional Code & Configuration (YAML/Shell/JSON) Editor for Kuma.
/// Features:
/// - Direct `Return` / `Enter` for newlines
/// - `Tab` key inserts 2 spaces indentation (does not lose focus)
/// - Pure monospaced typography with syntax formatting guards (no smart quotes/dashes)
/// - Clean dark terminal viewport with line number guides & integrated clipboard copy
public struct KumaCodeEditor: View {
    public let label: String
    @Binding public var code: String
    public var placeholder: String
    public var minHeight: CGFloat
    public var maxHeight: CGFloat?
    public var isReadOnly: Bool
    public var showsChrome: Bool
    /// When `false`, the text view ignores automatic first-responder until the user clicks inside it.
    private var allowsKeyboardFocusBinding: Binding<Bool>?

    private var focusBinding: Binding<Bool>?
    @State private var defaultFocus: Bool = false
    @State private var defaultAllowsKeyboardFocus: Bool = true
    @State private var copiedRecently: Bool = false

    private var effectiveFocus: Binding<Bool> {
        focusBinding ?? $defaultFocus
    }

    private var effectiveAllowsKeyboardFocus: Binding<Bool> {
        allowsKeyboardFocusBinding ?? $defaultAllowsKeyboardFocus
    }

    public init(
        label: String = "",
        code: Binding<String>,
        placeholder: String = "",
        minHeight: CGFloat = 140,
        maxHeight: CGFloat? = nil,
        isReadOnly: Bool = false,
        showsChrome: Bool = true,
        isFocused: Binding<Bool>? = nil,
        allowsKeyboardFocus: Binding<Bool>? = nil
    ) {
        self.label = label
        self._code = code
        self.placeholder = placeholder
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.isReadOnly = isReadOnly
        self.showsChrome = showsChrome
        self.focusBinding = isFocused
        self.allowsKeyboardFocusBinding = allowsKeyboardFocus
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KumaSpacing.xs) {
            if !label.isEmpty {
                HStack {
                    Text(label)
                        .font(KumaFont.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if !code.isEmpty {
                        Button {
                            copyCode()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: copiedRecently ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 9))
                                Text(copiedRecently ? "Copied" : "Copy")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            editorViewport
        }
    }

    private var placeholderLeadingInset: CGFloat {
        let chromePad: CGFloat = showsChrome ? 2 : 0
        return chromePad + KumaCodeEditorStyle.textInset
    }

    private var placeholderTopInset: CGFloat {
        let chromePad: CGFloat = showsChrome ? 2 : 0
        return chromePad + KumaCodeEditorStyle.textInset
    }

    @ViewBuilder
    private var editorViewport: some View {
        let viewport = ZStack(alignment: .topLeading) {
            KumaNativeCodeTextView(
                text: $code,
                minHeight: minHeight,
                maxHeight: maxHeight,
                isReadOnly: isReadOnly,
                isFocused: effectiveFocus,
                allowsKeyboardFocus: effectiveAllowsKeyboardFocus,
                onUserRequestedFocus: {
                    effectiveAllowsKeyboardFocus.wrappedValue = true
                }
            )
            .frame(minHeight: minHeight, maxHeight: maxHeight)

            if code.isEmpty {
                Text(placeholder)
                    .font(KumaCodeEditorStyle.swiftUIFont)
                    .foregroundStyle(Color(nsColor: .placeholderTextColor))
                    .padding(.leading, placeholderLeadingInset)
                    .padding(.top, placeholderTopInset)
                    .allowsHitTesting(false)
            }
        }

        if showsChrome {
            viewport
                .padding(2)
                .background(KumaColors.inputFieldFill, in: RoundedRectangle(cornerRadius: KumaRadius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: KumaRadius.sm, style: .continuous)
                        .stroke(
                            effectiveFocus.wrappedValue ? Color.accentColor : KumaColors.inputFieldStroke,
                            lineWidth: effectiveFocus.wrappedValue ? 1.5 : 0.5
                        )
                )
        } else {
            viewport
                .overlay(
                    RoundedRectangle(cornerRadius: KumaRadius.sm, style: .continuous)
                        .stroke(
                            effectiveFocus.wrappedValue ? Color.accentColor : Color.clear,
                            lineWidth: effectiveFocus.wrappedValue ? 1.5 : 0
                        )
                )
        }
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        withAnimation { copiedRecently = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { copiedRecently = false }
        }
    }
}

// MARK: - KumaNativeCodeTextView

private struct KumaNativeCodeTextView: NSViewRepresentable {
    @Binding var text: String
    let minHeight: CGFloat
    let maxHeight: CGFloat?
    let isReadOnly: Bool
    @Binding var isFocused: Bool
    @Binding var allowsKeyboardFocus: Bool
    let onUserRequestedFocus: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let contentSize = scrollView.contentSize
        let textView = CodeNSTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.focusGate = context.coordinator
        textView.onFocusChange = { [weak coordinator = context.coordinator] focused in
            Task { @MainActor in
                coordinator?.setFocused(focused)
            }
        }
        textView.minSize = NSSize(width: 0.0, height: minHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(
            width: KumaCodeEditorStyle.textInset,
            height: KumaCodeEditorStyle.textInset
        )

        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.allowsUndo = true
        textView.isEditable = !isReadOnly
        textView.isSelectable = true

        // Developer code settings (disable autocorrect / smart punctuation, match native text field colors)
        textView.font = KumaCodeEditorStyle.nsFont
        textView.textColor = NSColor.labelColor
        textView.insertionPointColor = NSColor.controlAccentColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        textView.string = text
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard !context.coordinator.isDismantled else { return }
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }
        textView.isEditable = !isReadOnly
        context.coordinator.onUserRequestedFocus = onUserRequestedFocus

        if allowsKeyboardFocus {
            context.coordinator.allowsKeyboardFocus = true
        } else if nsView.window?.firstResponder !== textView {
            context.coordinator.allowsKeyboardFocus = false
        }

        if !context.coordinator.allowsKeyboardFocus,
           nsView.window?.firstResponder === textView {
            nsView.window?.makeFirstResponder(nil)
            if isFocused { isFocused = false }
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.isDismantled = true
        guard let textView = nsView.documentView as? NSTextView else { return }
        if nsView.window?.firstResponder === textView {
            nsView.window?.makeFirstResponder(nil)
        }
        textView.delegate = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: KumaNativeCodeTextView
        var isDismantled = false
        var allowsKeyboardFocus = true
        var onUserRequestedFocus: (() -> Void)?

        init(_ parent: KumaNativeCodeTextView) {
            self.parent = parent
        }

        func grantKeyboardFocusFromUserClick() {
            onUserRequestedFocus?()
            allowsKeyboardFocus = true
        }

        func textDidChange(_ notification: Notification) {
            guard !isDismantled else { return }
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func setFocused(_ focused: Bool) {
            guard !isDismantled else { return }
            guard parent.isFocused != focused else { return }
            parent.isFocused = focused
        }
    }
}

// MARK: - CodeNSTextView (Custom Key Events for Tab Indentation)

private final class CodeNSTextView: NSTextView {
    weak var focusGate: KumaNativeCodeTextView.Coordinator?
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        guard focusGate?.allowsKeyboardFocus ?? true else { return false }
        let became = super.becomeFirstResponder()
        if became { onFocusChange?(true) }
        return became
    }

    override func mouseDown(with event: NSEvent) {
        let gateOpen = focusGate?.allowsKeyboardFocus ?? true
        if !gateOpen {
            focusGate?.grantKeyboardFocusFromUserClick()
            window?.makeFirstResponder(self)
        }
        super.mouseDown(with: event)
        if window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocusChange?(false) }
        return resigned
    }

    override func keyDown(with event: NSEvent) {
        // Tab key: Insert 2 spaces instead of shifting UI focus
        if event.keyCode == 48 { // KeyCode 48 is Tab
            self.insertText("  ", replacementRange: self.selectedRange())
            return
        }
        super.keyDown(with: event)
    }
}
