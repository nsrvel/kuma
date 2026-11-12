import SwiftUI

public struct ServiceCardView: View, Equatable {
    public let snapshot: ServiceCardSnapshot
    public let runtime: ServiceRuntimeState
    public let isSelected: Bool

    @Environment(\.serviceDeckActions) private var deckActions

    public init(
        snapshot: ServiceCardSnapshot,
        runtime: ServiceRuntimeState = .idle,
        isSelected: Bool = false
    ) {
        self.snapshot = snapshot
        self.runtime = runtime
        self.isSelected = isSelected
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    ZStack(alignment: .topTrailing) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    snapshot.isDisabled
                                    ? LinearGradient(colors: [Color.secondary.opacity(0.18), Color.secondary.opacity(0.24)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : snapshot.providerCategory.gradient
                                )
                                .frame(width: 34, height: 34)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.black.opacity(snapshot.isDisabled ? 0 : 0.08), lineWidth: 1)
                                }

                            ProviderBrandIcon(category: snapshot.providerCategory, size: 16, rasterize: false)
                                .foregroundStyle(snapshot.isDisabled ? Color.secondary : Color.white)
                        }

                        if snapshot.isStarred {
                            ZStack {
                                Circle()
                                    .fill(Color(nsColor: .windowBackgroundColor))
                                    .frame(width: 14, height: 14)

                                Image(systemName: "star.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Color.yellow)
                            }
                            .offset(x: 4, y: -4)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(snapshot.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(snapshot.isDisabled ? .secondary : .primary)
                            .lineLimit(1)

                        Text(targetSubtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                CardToggleSwitch(
                    isDisabled: snapshot.isDisabled,
                    runtime: runtime,
                    onToggle: { deckActions?.onToggle(snapshot.id) }
                )
            }

            HStack(spacing: 6) {
                if !snapshot.portDisplays.isEmpty {
                    PortChipsView(ports: snapshot.portDisplays, limit: 3)
                } else {
                    ServiceNonPortBadge(category: snapshot.providerCategory)
                }

                Spacer(minLength: 4)

                ServiceStatusObserver(state: runtime, isDisabled: snapshot.isDisabled, deckStyle: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KumaColors.surfaceBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onTapGesture {
            deckActions?.onSelect(snapshot.id)
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2.0)
            }
        }
        .opacity(snapshot.isDisabled ? 0.65 : 1.0)
        .contextMenu {
            ServiceCardContextMenu(snapshot: snapshot, runtime: runtime)
        }
    }

    private var targetSubtitle: String {
        if snapshot.providerCategory == .kubernetes,
           let live = KubeLiveTargetDisplay.resolvedName(for: snapshot.id) {
            return "k8s: \(live)"
        }
        if !snapshot.subtitle.isEmpty {
            return snapshot.subtitle
        }
        return snapshot.providerCategory.sidebarLabel
    }
}

#Preview {
    ServiceCardView(
        snapshot: ServiceCardSnapshot(id: UUID(), name: "Preview API", providerCategory: .kubernetes, portDisplays: [8080]),
        runtime: ServiceRuntimeState(status: .running, isLoading: false),
        isSelected: false
    )
    .frame(width: KumaTheme.Deck.cardIdealWidth)
    .padding()
}

extension ServiceCardView {
    nonisolated public static func == (lhs: ServiceCardView, rhs: ServiceCardView) -> Bool {
        lhs.snapshot == rhs.snapshot &&
        lhs.runtime.status == rhs.runtime.status &&
        lhs.runtime.isLoading == rhs.runtime.isLoading &&
        lhs.isSelected == rhs.isSelected
    }
}
