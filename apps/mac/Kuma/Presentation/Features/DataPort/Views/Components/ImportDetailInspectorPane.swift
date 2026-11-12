import SwiftUI

public struct ImportDetailInspectorPane: View {
    public let serviceName: String
    public let serviceDescription: String?
    public let provider: DataPortService.ExportProvider?
    public let portMappings: [DataPortService.ExportPortMapping]
    public let hasConflict: Bool

    public init(
        serviceName: String,
        serviceDescription: String? = nil,
        provider: DataPortService.ExportProvider?,
        portMappings: [DataPortService.ExportPortMapping],
        hasConflict: Bool = false
    ) {
        self.serviceName = serviceName
        self.serviceDescription = serviceDescription
        self.provider = provider
        self.portMappings = portMappings
        self.hasConflict = hasConflict
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header: Provider Gradient Icon + Title & Conflict Status
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(providerCategory.gradient)
                            .frame(width: 32, height: 32)
                            .shadow(color: Color.black.opacity(0.12), radius: 2, y: 1)

                        Image(systemName: providerCategory.icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(serviceName)
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if hasConflict {
                            Text("Name exists in workspace (will auto-rename)")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.orange)
                        } else if let desc = serviceDescription, !desc.isEmpty {
                            Text(desc)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text(providerCategory.sidebarLabel)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider().opacity(0.3)

                // Section 1: Clean Provider Configuration
                if let p = provider {
                    ImportConfigurationSectionView(provider: p, category: providerCategory)
                }

                // Section 2: Port Mappings
                if !portMappings.isEmpty {
                    Divider().opacity(0.3)
                    ImportPortMappingsSectionView(portMappings: portMappings)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KumaColors.surfaceBackground.opacity(0.5))
    }

    private var providerCategory: ProviderCategory {
        provider?.category ?? .docker
    }
}
