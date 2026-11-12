import SwiftUI
import AppKit

// MARK: - KumaTextField

public struct KumaTextField: View {
    public let label: String
    @Binding public var value: String
    public var placeholder: String
    public var error: String?
    public var autoFocus: Bool
    public var onSubmit: (() -> Void)?

    @FocusState private var isFocused: Bool

    public init(
        label: String,
        value: Binding<String>,
        placeholder: String = "",
        error: String? = nil,
        autoFocus: Bool = false,
        onSubmit: (() -> Void)? = nil
    ) {
        self.label = label
        self._value = value
        self.placeholder = placeholder
        self.error = error
        self.autoFocus = autoFocus
        self.onSubmit = onSubmit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KumaSpacing.xs) {
            if !label.isEmpty {
                Text(label)
                    .font(KumaFont.caption)
                    .foregroundStyle(.secondary)
            }

            ZStack(alignment: .leading) {
                if value.isEmpty {
                    Text(placeholder)
                        .font(KumaFont.body)
                        .foregroundStyle(Color(nsColor: .placeholderTextColor))
                        .allowsHitTesting(false)
                }

                TextField("", text: $value)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color.primary)
                    .focused($isFocused)
                    .onSubmit {
                        onSubmit?()
                    }
            }
                .padding(KumaSpacing.sm)
                .background(KumaColors.inputFieldFill, in: RoundedRectangle(cornerRadius: KumaRadius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: KumaRadius.sm, style: .continuous)
                        .stroke(
                            isFocused ? Color.accentColor : KumaColors.inputFieldStroke,
                            lineWidth: isFocused ? 1.5 : 0.5
                        )
                )

                .onAppear {
                    if autoFocus {
                        isFocused = true
                    }
                }


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
        @State private var text1 = "127.0.0.1"
        @State private var text2 = "invalid-port-abc"
        var body: some View {
            VStack(spacing: 16) {
                KumaTextField(
                    label: "Host IP Address",
                    value: $text1,
                    placeholder: "localhost"
                )
                KumaTextField(
                    label: "Port Number",
                    value: $text2,
                    placeholder: "8080",
                    error: "Port must be a valid integer between 1 and 65535"
                )
            }
            .padding()
            .frame(width: 400)
        }
    }
    return PreviewWrapper()
}
