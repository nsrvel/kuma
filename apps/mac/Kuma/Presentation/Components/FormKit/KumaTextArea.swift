import SwiftUI

// MARK: - KumaTextArea

/// A multi-line plain text area for descriptions, notes, and multi-line inputs.
/// Built with pure SwiftUI native `TextField(axis: .vertical)` matching `KumaTextField` 1:1.
public struct KumaTextArea: View {
    public let label: String
    @Binding public var value: String
    public var placeholder: String
    public var minHeight: CGFloat
    public var maxHeight: CGFloat?
    public var isMonospaced: Bool
    public var lineLimit: ClosedRange<Int>
    public var error: String?

    @FocusState private var isFocused: Bool

    public init(
        label: String = "",
        value: Binding<String>,
        placeholder: String = "",
        minHeight: CGFloat = 52,
        maxHeight: CGFloat? = nil,
        isMonospaced: Bool = false,
        lineLimit: ClosedRange<Int> = 2...5,
        error: String? = nil
    ) {
        self.label = label
        self._value = value
        self.placeholder = placeholder
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.isMonospaced = isMonospaced
        self.lineLimit = lineLimit
        self.error = error
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KumaSpacing.xs) {
            if !label.isEmpty {
                Text(label)
                    .font(KumaFont.caption)
                    .foregroundStyle(.secondary)
            }

            ZStack(alignment: .topLeading) {
                if value.isEmpty {
                    Text(placeholder)
                        .font(isMonospaced ? .system(size: 11.5, weight: .regular, design: .monospaced) : KumaFont.body)
                        .foregroundStyle(Color(nsColor: .placeholderTextColor))
                        .allowsHitTesting(false)
                }

                TextField("", text: $value, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(isMonospaced ? .system(size: 11.5, weight: .regular, design: .monospaced) : KumaFont.body)
                    .foregroundStyle(Color.primary)
                    .lineLimit(lineLimit)
            }
            .frame(minHeight: minHeight, maxHeight: maxHeight, alignment: .topLeading)
            .focused($isFocused)
            .padding(KumaSpacing.sm)
            .background(KumaColors.inputFieldFill, in: RoundedRectangle(cornerRadius: KumaRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: KumaRadius.sm, style: .continuous)
                    .stroke(
                        isFocused ? Color.accentColor : KumaColors.inputFieldStroke,
                        lineWidth: isFocused ? 1.5 : 0.5
                    )
            )

            if let error, !error.isEmpty {
                Text(error)
                    .font(KumaFont.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var notes = ""
        @State private var filledNotes = "Local PostgreSQL database for development.\nConnect via psql or DBeaver on port 5432."

        var body: some View {
            VStack(spacing: 20) {
                KumaTextArea(
                    label: "Description / Notes (Empty)",
                    value: $notes,
                    placeholder: "Service purpose or notes..."
                )

                KumaTextArea(
                    label: "Description / Notes (Filled)",
                    value: $filledNotes,
                    placeholder: "Service purpose or notes..."
                )
            }
            .padding()
            .frame(width: 440)
            .background(KumaColors.canvasBackground)
        }
    }
    return PreviewWrapper()
}

