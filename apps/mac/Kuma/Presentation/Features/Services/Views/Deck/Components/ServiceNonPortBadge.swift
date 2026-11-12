import SwiftUI

// MARK: - ServiceNonPortBadge

public struct ServiceNonPortBadge: View {
    public let category: ProviderCategory

    public init(category: ProviderCategory) {
        self.category = category
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.2.layers.3d.bottom.filled")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)

            Text(category.sidebarLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
        .fixedSize()
    }
}

#Preview {
    HStack(spacing: 8) {
        ServiceNonPortBadge(category: .docker)
        ServiceNonPortBadge(category: .shell)
        ServiceNonPortBadge(category: .httpCheck)
    }
    .padding()
}
