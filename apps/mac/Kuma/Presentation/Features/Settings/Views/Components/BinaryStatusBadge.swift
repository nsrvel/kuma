import SwiftUI

// MARK: - BinaryStatusBadge

public struct BinaryStatusBadge: View {
    public let isInstalled: Bool

    public init(isInstalled: Bool) {
        self.isInstalled = isInstalled
    }

    public var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isInstalled ? Color.green : Color.red.opacity(0.8))
                .frame(width: 6, height: 6)
            Text(isInstalled ? "Available" : "Not Found")
                .font(KumaFont.caption)
                .foregroundStyle(isInstalled ? Color.secondary : Color.red.opacity(0.8))
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        BinaryStatusBadge(isInstalled: true)
        BinaryStatusBadge(isInstalled: false)
    }
    .padding()
}
