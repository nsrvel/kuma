import SwiftUI

public struct CreateServiceProviderStepView: View {
    @Binding public var selectedProvider: ProviderCategory
    public var onContinue: () -> Void
    public var onCancel: () -> Void

    public init(
        selectedProvider: Binding<ProviderCategory>,
        onContinue: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._selectedProvider = selectedProvider
        self.onContinue = onContinue
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("Select Provider")
                    .font(.system(size: 16, weight: .bold))
                Text("Choose how this service will run")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                providerCard(category: .kubernetes, title: "Kubernetes", desc: "Port-forward service pods")
                providerCard(category: .docker, title: "Docker", desc: "Container & service daemon")
                providerCard(category: .podman, title: "Podman", desc: "Podman container daemon")
                providerCard(category: .shell, title: "Shell", desc: "Local CLI shell daemon")
                providerCard(category: .ssh, title: "SSH", desc: "Remote SSH host runner")
                providerCard(category: .httpCheck, title: "Health Check", desc: "Ping endpoint health")
                providerCard(category: .tunnel, title: "Tunnel", desc: "Cloudflare / Ngrok tunnel")
                providerCard(category: .processMonitor, title: "Process Monitor", desc: "Track OS process state")
            }
            .padding(.horizontal, 24)

            Spacer()

            Divider().opacity(0.4)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    @ViewBuilder
    private func providerCard(category: ProviderCategory, title: String, desc: String) -> some View {
        let isSelected = selectedProvider == category

        Button {
            selectedProvider = category
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(category.gradient)
                        .frame(width: 32, height: 32)
                        .shadow(color: .black.opacity(0.16), radius: 2, y: 1)

                    ProviderBrandIcon(category: category, size: 16)
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    Text(desc)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : KumaColors.surfaceBackground)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : KumaColors.borderSubtle,
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            }
        }
        .buttonStyle(.plain)
    }
}
