import SwiftUI
import UniformTypeIdentifiers

public struct DependencyStatusRowView: View {
    let dependency: SystemDependency
    var isScanning: Bool = false
    var onBrowse: ((String) -> Void)? = nil

    @State private var isFileImporterPresented = false

    public init(
        dependency: SystemDependency,
        isScanning: Bool = false,
        onBrowse: ((String) -> Void)? = nil
    ) {
        self.dependency = dependency
        self.isScanning = isScanning
        self.onBrowse = onBrowse
    }

    private var allowedContentTypes: [UTType] {
        if dependency.id == "kubeconfig" {
            var types: [UTType] = [.plainText]
            if let yamlType = UTType(filenameExtension: "yaml") { types.append(yamlType) }
            if let ymlType = UTType(filenameExtension: "yml") { types.append(ymlType) }
            return types
        }
        return [.unixExecutable, .executable]
    }

    public var body: some View {
        KumaCard(padding: KumaSpacing.md) {
            HStack(spacing: KumaSpacing.md) {
                // Icon Container (Consistent brand styling)
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 28, height: 28)

                    dependencyIconView
                        .foregroundStyle(.primary)
                }

                // Info Column
                VStack(alignment: .leading, spacing: 2) {
                    Text(dependency.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)

                    if isScanning {
                        Text("Checking PATH…")
                            .font(KumaFont.subheadline)
                            .foregroundStyle(.secondary)
                    } else if let path = dependency.path, !path.isEmpty {
                        Text(path)
                            .font(KumaFont.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Not detected")
                            .font(KumaFont.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: KumaSpacing.sm)

                // Action / Status Area:
                // - Spinner during scan
                // - 'Ready' pill if detected
                // - 'Browse…' button if missing/not detected
                if isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                        .fixedSize()
                } else if (dependency.path?.isEmpty == false) || dependency.isInstalled {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.green)

                        Text("Ready")
                            .font(KumaFont.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 2)
                } else if onBrowse != nil {
                    Button("Browse") {
                        isFileImporterPresented = true
                    }
                    .font(KumaFont.subheadline)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Browse executable for \(dependency.name)")
                }
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let selectedURL = urls.first {
                onBrowse?(selectedURL.path(percentEncoded: false))
            }
        }
    }

    @ViewBuilder
    private var dependencyIconView: some View {
        switch dependency.id {
        case "docker":
            ProviderBrandIcon(category: .docker, size: 15)
        case "kubectl":
            ProviderBrandIcon(category: .kubernetes, size: 15)
        case "kubeconfig":
            Image(systemName: "doc.text.fill")
                .font(.system(size: 13, weight: .medium))
        case "podman":
            ProviderBrandIcon(category: .podman, size: 15)
        case "ngrok":
            NgrokBrandVector()
                .frame(width: 15, height: 15)
        case "cloudflared":
            Image(systemName: "cloud.bolt.fill")
                .font(.system(size: 13, weight: .medium))
        default:
            Image(systemName: dependency.iconName)
                .font(.system(size: 13, weight: .medium))
        }
    }
}

#Preview("Available") {
    DependencyStatusRowView(
        dependency: SystemDependency(
            id: "docker",
            name: "Docker Engine",
            iconName: "shippingbox.fill",
            isInstalled: true,
            path: "/opt/homebrew/bin/docker"
        )
    )
    .padding()
}

#Preview("Not Found") {
    DependencyStatusRowView(
        dependency: SystemDependency(
            id: "podman",
            name: "Podman Engine",
            iconName: "cylinder.split.1x2.fill",
            isInstalled: false
        ),
        onBrowse: { _ in }
    )
    .padding()
}
