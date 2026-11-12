import SwiftUI

public struct PublicTunnelingStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    public init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: KumaSpacing.lg) {
            // Title & Subtitle
            VStack(spacing: KumaSpacing.xs) {
                Text("Public Tunneling")
                    .font(KumaFont.stepTitle)
                    .foregroundStyle(.primary)

                Text("Optional utilities to expose local services to the internet.")
                    .font(KumaFont.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, KumaSpacing.sm)

            // Content List
            VStack(spacing: KumaSpacing.sm) {
                ForEach(viewModel.tunnelingDependencies) { dep in
                    DependencyStatusRowView(
                        dependency: dep,
                        isScanning: viewModel.isScanning,
                        onBrowse: { path in
                            viewModel.setCustomPath(for: dep, path: path)
                        }
                    )
                }
            }

            // Borderless Ghost Re-scan Link (Subtle secondary action)
            Button {
                Task {
                    await viewModel.runScan(isManualRescan: true)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                    Text(viewModel.isScanning ? "Scanning…" : "Re-scan")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Re-scan Public Tunneling tools")
            .disabled(viewModel.isScanning)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            await viewModel.scanDependenciesIfNeeded()
        }
    }
}

#Preview {
    PublicTunnelingStepView(viewModel: OnboardingViewModel())
        .frame(width: 600, height: 400)
}
