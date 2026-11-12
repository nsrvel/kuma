import SwiftUI

/// Shared chrome for inline expanded form editors (header, footer, panel stroke).
public struct KumaFormInlinePanel<Content: View>: View {
    public let headerTitle: String
    public let headerIcon: String
    public let closeAccessibilityLabel: String
    public let primaryTitle: String
    public var primaryDisabled: Bool
    @ViewBuilder public let content: () -> Content
    public let showsCommitFooter: Bool
    public var showsCancelInFooter: Bool
    public let onCancel: () -> Void
    public let onPrimary: () -> Void

    public init(
        headerTitle: String,
        headerIcon: String,
        closeAccessibilityLabel: String,
        primaryTitle: String = "Save",
        primaryDisabled: Bool = false,
        showsCommitFooter: Bool = true,
        showsCancelInFooter: Bool = true,
        onCancel: @escaping () -> Void,
        onPrimary: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.headerTitle = headerTitle
        self.headerIcon = headerIcon
        self.closeAccessibilityLabel = closeAccessibilityLabel
        self.primaryTitle = primaryTitle
        self.primaryDisabled = primaryDisabled
        self.showsCommitFooter = showsCommitFooter
        self.showsCancelInFooter = showsCancelInFooter
        self.onCancel = onCancel
        self.onPrimary = onPrimary
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KumaSpacing.md) {
            HStack {
                Label(headerTitle, systemImage: headerIcon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(closeAccessibilityLabel)
            }

            content()
                .frame(maxWidth: .infinity, alignment: .leading)

            if showsCommitFooter {
                KumaFormCommitFooter(
                    primaryTitle: primaryTitle,
                    primaryDisabled: primaryDisabled,
                    showsCancel: showsCancelInFooter,
                    onCancel: onCancel,
                    onPrimary: onPrimary
                )
            }
        }
        .padding(KumaSpacing.md)
        .background(KumaColors.inputBackground.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: KumaRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KumaRadius.md, style: .continuous)
                .strokeBorder(KumaColors.inputBorder, lineWidth: 0.5)
        )
    }
}
