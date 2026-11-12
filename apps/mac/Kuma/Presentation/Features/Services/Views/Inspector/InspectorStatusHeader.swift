import SwiftUI

/// Native macOS fixed header zone for the Service Inspector.
/// Displays service identity, provider type, live status observer, and start/stop button.
public struct InspectorStatusHeader: View {
    public let service: Service
    public let provider: Provider?
    public let runtime: ServiceRuntimeState
    public var isViewingLogs: Bool = false
    public var isStartDisabled: Bool = false
    public let onToggle: () -> Void
    public var onBack: () -> Void = {}

    public init(
        service: Service,
        provider: Provider?,
        runtime: ServiceRuntimeState,
        isViewingLogs: Bool = false,
        isStartDisabled: Bool = false,
        onToggle: @escaping () -> Void,
        onBack: @escaping () -> Void = {}
    ) {
        self.service = service
        self.provider = provider
        self.runtime = runtime
        self.isViewingLogs = isViewingLogs
        self.isStartDisabled = isStartDisabled
        self.onToggle = onToggle
        self.onBack = onBack
    }

    private var category: ProviderCategory {
        provider?.type ?? .docker
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if isViewingLogs {
                    Button {
                        onBack()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                                .frame(width: 32, height: 32)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
                                }

                            Image(systemName: "chevron.left")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to configuration")
                    .help("Back to Configuration")
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    ZStack(alignment: .topTrailing) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(service.isDisabled
                                      ? LinearGradient(colors: [.secondary.opacity(0.18), .secondary.opacity(0.24)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                      : category.gradient)
                                .frame(width: 32, height: 32)
                                .shadow(color: .black.opacity(service.isDisabled ? 0 : 0.14), radius: 2, y: 1)

                            ProviderBrandIcon(category: category, tunnelType: provider?.tunnelType, size: 16)
                                .foregroundStyle(service.isDisabled ? Color.secondary : Color.white)
                        }

                        if service.isStarred {
                            ZStack {
                                Circle()
                                    .fill(Color(nsColor: .windowBackgroundColor))
                                    .frame(width: 13, height: 13)

                                Image(systemName: "star.fill")
                                    .font(.system(size: 7.5, weight: .bold))
                                    .foregroundStyle(Color.yellow)
                            }
                            .offset(x: 3.5, y: -3.5)
                            .shadow(color: Color.black.opacity(0.15), radius: 1, y: 0.5)
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(service.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(service.isDisabled ? .secondary : .primary)

                    Text(category.sidebarLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if service.isDisabled {
                    Image(systemName: "lock.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 8)
                } else {
                    InspectorHeaderActionButton(
                        runtime: runtime,
                        isStartDisabled: isStartDisabled,
                        onToggle: onToggle
                    )
                }
            }
        }
        .padding(.horizontal, KumaSpacing.lg)
        .padding(.vertical, KumaSpacing.md)
    }
}

#Preview {
    InspectorStatusHeader(
        service: Service(name: "Preview Service", workspaceID: UUID()),
        provider: nil,
        runtime: .idle,
        onToggle: {}
    )
    .frame(width: 400)
}
