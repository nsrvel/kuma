import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - WorkspaceAvatarPickerView

public struct WorkspaceAvatarPickerView: View {
    public let name: String
    @Binding public var selectedImagePath: String?
    @Binding public var selectedImageURL: URL?

    @State private var isHoveringAvatar = false

    private var hasCustomPhoto: Bool {
        selectedImageURL != nil || selectedImagePath != nil
    }

    public init(
        name: String,
        selectedImagePath: Binding<String?>,
        selectedImageURL: Binding<URL?>
    ) {
        self.name = name
        self._selectedImagePath = selectedImagePath
        self._selectedImageURL = selectedImageURL
    }

    public var body: some View {
        Button(action: selectImage) {
            avatarCard
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Workspace photo")
        .accessibilityHint("Select to choose a new photo")
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                isHoveringAvatar = hovering
            }
        }
        .contextMenu {
            Button(action: selectImage) {
                Label("Choose Photo", systemImage: "photo")
            }
            if hasCustomPhoto {
                Divider()
                Button(role: .destructive, action: removePhoto) {
                    Label("Remove Photo", systemImage: "trash")
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if hasCustomPhoto {
                WorkspaceAvatarRemoveBadge(onRemove: removePhoto)
                    .offset(x: 6, y: -6)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .padding(.top, 6)
        .padding(.trailing, 6)
    }

    // MARK: - Subviews

    private var avatarCard: some View {
        ZStack {
            WorkspaceAvatarView(
                name: name.isEmpty ? "Workspace" : name,
                imagePath: selectedImageURL?.path(percentEncoded: false) ?? selectedImagePath,
                size: 80
            )

            // Hover Scrim & Single Center Camera Icon
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(isHoveringAvatar ? 0.32 : 0.0))
                .overlay(
                    Image(systemName: "camera.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .scaleEffect(isHoveringAvatar ? 1.0 : 0.75)
                        .opacity(isHoveringAvatar ? 1.0 : 0.0)
                )
        }
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 6, y: 3)
    }

    // MARK: - Actions

    private func selectImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]

        if panel.runModal() == .OK, let url = panel.url {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                self.selectedImageURL = url
                self.selectedImagePath = url.path(percentEncoded: false)
            }
        }
    }

    private func removePhoto() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            self.selectedImagePath = nil
            self.selectedImageURL = nil
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var pathNoImg: String? = nil
        @State private var urlNoImg: URL? = nil

        @State private var pathWithImg: String? = "/tmp/mock.png"
        @State private var urlWithImg: URL? = URL(fileURLWithPath: "/tmp/mock.png")

        var body: some View {
            HStack(spacing: 32) {
                VStack(spacing: 8) {
                    WorkspaceAvatarPickerView(name: "Default Space", selectedImagePath: $pathNoImg, selectedImageURL: $urlNoImg)
                    Text("No Photo").font(.caption).foregroundStyle(.secondary)
                }

                VStack(spacing: 8) {
                    WorkspaceAvatarPickerView(name: "Production Backend", selectedImagePath: $pathWithImg, selectedImageURL: $urlWithImg)
                    Text("With Photo").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
    }
    return PreviewWrapper()
}
