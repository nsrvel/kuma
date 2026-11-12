import SwiftUI

public struct KumaEmptyStateView: View {
    public let iconName: String
    public let title: String
    public let description: String
    public var actionButtonTitle: String?
    public var action: (() -> Void)?

    public init(
        iconName: String,
        title: String,
        description: String,
        actionButtonTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.iconName = iconName
        self.title = title
        self.description = description
        self.actionButtonTitle = actionButtonTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: KumaSpacing.md) {
            Image(systemName: iconName)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.secondary.opacity(0.6))
                .padding(.bottom, KumaSpacing.xs)

            Text(title)
                .font(KumaFont.title3)
                .foregroundStyle(.primary)

            Text(description)
                .font(KumaFont.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            if let actionButtonTitle, let action {
                Button(action: action) {
                    Text(actionButtonTitle)
                        .font(KumaFont.bodyMedium)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.top, KumaSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(KumaSpacing.xxl)
    }
}

#Preview {
    KumaEmptyStateView(
        iconName: "square.stack.3d.up.slash",
        title: "No Services Yet",
        description: "Create a service to start port-forwarding, container, or shell runs.",
        actionButtonTitle: "Create Service",
        action: {}
    )
    .frame(width: 450, height: 350)
}
