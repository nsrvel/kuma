import SwiftUI

public struct KubeConfigItemRowView: View {
    let config: KubeConfig
    let isSelected: Bool
    let isLocked: Bool
    let isLoadingNamespaces: Bool
    let hasConnectionError: Bool
    let contextToTest: String
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onRefresh: () -> Void

    @State private var isHovered: Bool = false

    public init(
        config: KubeConfig,
        isSelected: Bool,
        isLocked: Bool = false,
        isLoadingNamespaces: Bool,
        hasConnectionError: Bool,
        contextToTest: String,
        onSelect: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onRefresh: @escaping () -> Void
    ) {
        self.config = config
        self.isSelected = isSelected
        self.isLocked = isLocked
        self.isLoadingNamespaces = isLoadingNamespaces
        self.hasConnectionError = hasConnectionError
        self.contextToTest = contextToTest
        self.onSelect = onSelect
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onRefresh = onRefresh
    }

    private var connectionTone: Color {
        if isLoadingNamespaces { return KumaStatus.transitionalIndicator }
        if hasConnectionError { return KumaStatus.failedIndicator }
        return KumaStatus.runningIndicator
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(config.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)

                Text(subtitleText)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isSelected {
                connectionStatusChip
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .animation(.easeInOut(duration: 0.2), value: isLoadingNamespaces)
        .animation(.easeInOut(duration: 0.2), value: hasConnectionError)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background { KumaInspectorListRowSelectionChrome(isSelected: isSelected, isHovered: isHovered) }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            if !isLocked {
                if !config.isDefault {
                    Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
                    Divider()
                    Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
                } else {
                    Button { onRefresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                }
            }
        }
        .onTapGesture {
            if !isLocked {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                    onSelect()
                }
            }
        }
    }

    private var subtitleText: String {
        if config.isDefault {
            if let path = config.sourceFilePath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                return Self.displayPath(path)
            }
            return "~/.kube/config"
        }
        if let path = config.sourceFilePath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            return (path as NSString).lastPathComponent
        }
        if !config.configContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Paste Config"
        }
        return "Custom Config"
    }

    private static func displayPath(_ path: String) -> String {
        let home = DependencyChecker.userHomePath()
        if path.hasPrefix(home + "/") {
            return "~/" + path.dropFirst(home.count + 1)
        }
        return path
    }

    @ViewBuilder
    private var connectionStatusChip: some View {
        if isLoadingNamespaces {
            KumaStatusChip(title: "Connecting…", tone: connectionTone, showsOrbit: true, showsContainer: false)
        } else if hasConnectionError {
            KumaStatusChip(title: "Unreachable", tone: connectionTone, showsContainer: false)
        } else {
            KumaStatusChip(title: "Connected", tone: connectionTone, showsGlow: true, showsContainer: false)
        }
    }
}
