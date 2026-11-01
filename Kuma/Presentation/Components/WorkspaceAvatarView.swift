import SwiftUI
import AppKit

public struct WorkspaceAvatarView: View {
    public let name: String
    public let imagePath: String?
    public let size: CGFloat
    /// Busts SwiftUI caching when the workspace row updates but `imagePath` stays `{id}.png`.
    private let imageRefreshToken: TimeInterval?

    public init(name: String, imagePath: String? = nil, size: CGFloat = 24) {
        self.name = name
        self.imagePath = imagePath
        self.size = size
        self.imageRefreshToken = nil
    }

    public init(workspace: Workspace, size: CGFloat = 24) {
        self.name = workspace.name
        self.imagePath = workspace.imagePath
        self.size = size
        self.imageRefreshToken = workspace.updatedAt.timeIntervalSince1970
    }

    public var body: some View {
        ZStack {
            if let imgPath = imagePath, let nsImg = cachedImage(from: imgPath) {
                Image(nsImage: nsImg)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(avatarGradient)

                Text(initials)
                    .font(.system(size: size * 0.44, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .id(imageRefreshToken.map { "\(imagePath ?? "")-\($0)" } ?? imagePath)
    }

    private func cachedImage(from path: String) -> NSImage? {
        WorkspaceImageStore.shared.thumbnail(for: path, maxDimension: size * 2)
    }

    private var initials: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "W" }
        let words = trimmed.split(separator: " ")
        if let first = words.first?.first {
            return String(first).uppercased()
        }
        return "W"
    }

    private var avatarGradient: LinearGradient {
        let hash = abs(name.utf8.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1) })
        let palettes: [[Color]] = [
            [Color(red: 0.18, green: 0.48, blue: 0.96), Color(red: 0.35, green: 0.65, blue: 1.00)], // Blue
            [Color(red: 0.85, green: 0.18, blue: 0.85), Color(red: 0.95, green: 0.45, blue: 0.95)], // Pink/Purple
            [Color(red: 0.05, green: 0.75, blue: 0.45), Color(red: 0.25, green: 0.95, blue: 0.65)], // Green
            [Color(red: 0.95, green: 0.36, blue: 0.13), Color(red: 1.00, green: 0.60, blue: 0.30)], // Orange
            [Color(red: 0.58, green: 0.18, blue: 0.95), Color(red: 0.78, green: 0.45, blue: 1.00)]  // Indigo
        ]
        let colors = palettes[hash % palettes.count]
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

#Preview {
    HStack(spacing: 12) {
        WorkspaceAvatarView(name: "Default Workspace", size: 32)
        WorkspaceAvatarView(name: "Production Backend", size: 32)
        WorkspaceAvatarView(name: "Staging Cluster", size: 32)
        WorkspaceAvatarView(name: "Analytics Service", size: 32)
    }
    .padding()
}
