import SwiftUI

// MARK: - KumaToggleField

public struct KumaToggleField: View {
    public let label: String
    @Binding public var value: Bool
    public var description: String?

    public init(label: String, value: Binding<Bool>, description: String? = nil) {
        self.label = label
        self._value = value
        self.description = description
    }

    public var body: some View {
        HStack(alignment: .center, spacing: KumaSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(KumaFont.body)
                    .foregroundStyle(.primary)
                if let description {
                    Text(description)
                        .font(KumaFont.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: KumaSpacing.md)

            Toggle("", isOn: $value)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var isEnabled = true
        var body: some View {
            KumaToggleField(
                label: "Auto-Resume Services",
                value: $isEnabled,
                description: "Automatically start active services upon launching Kuma."
            )
            .padding()
            .frame(width: 450)
        }
    }
    return PreviewWrapper()
}
