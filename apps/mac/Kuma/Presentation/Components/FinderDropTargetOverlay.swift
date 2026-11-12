import SwiftUI

// MARK: - FinderDropTargetOverlay

public struct FinderDropTargetOverlay: View {
    public init() {}

    public var body: some View {
        Color.black.opacity(0.4)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(Color.accentColor)

                    Text("Drop JSON to Import Configuration")
                        .font(.system(size: 16, weight: .bold))

                    Text("Workspaces and services will be inspected before importing.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(32)
                .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 2)
                }
            }
            .transition(.opacity)
    }
}

#Preview {
    FinderDropTargetOverlay()
        .frame(width: 500, height: 400)
}
