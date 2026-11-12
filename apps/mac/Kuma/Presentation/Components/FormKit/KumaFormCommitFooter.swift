import SwiftUI

/// Cancel + primary action row for inline inspector form panels (aligned with field content width).
public struct KumaFormCommitFooter: View {
    public let primaryTitle: String
    public var primaryDisabled: Bool
    public var showsCancel: Bool
    public let onCancel: () -> Void
    public let onPrimary: () -> Void

    public init(
        primaryTitle: String,
        primaryDisabled: Bool = false,
        showsCancel: Bool = true,
        onCancel: @escaping () -> Void,
        onPrimary: @escaping () -> Void
    ) {
        self.primaryTitle = primaryTitle
        self.primaryDisabled = primaryDisabled
        self.showsCancel = showsCancel
        self.onCancel = onCancel
        self.onPrimary = onPrimary
    }

    public var body: some View {
        HStack(alignment: .center, spacing: KumaSpacing.sm) {
            if showsCancel {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }

            Spacer(minLength: KumaSpacing.sm)

            Button(primaryTitle, action: onPrimary)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(primaryDisabled)
        }
        .frame(maxWidth: .infinity)
    }
}
