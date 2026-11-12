import SwiftUI
import AppKit

// MARK: - KumaSecureField

public struct KumaSecureField: View {
    public let label: String
    @Binding public var value: String
    public var placeholder: String
    public var error: String?

    @FocusState private var isFocused: Bool

    public init(
        label: String,
        value: Binding<String>,
        placeholder: String = "",
        error: String? = nil
    ) {
        self.label = label
        self._value = value
        self.placeholder = placeholder
        self.error = error
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KumaSpacing.xs) {
            if !label.isEmpty {
                Text(label)
                    .font(KumaFont.caption)
                    .foregroundStyle(.secondary)
            }

            SecureField(placeholder, text: $value)
                .textFieldStyle(.plain)
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
