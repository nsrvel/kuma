import SwiftUI

public struct OnboardingWizardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var viewModel = OnboardingViewModel()
    @State private var isTransitioning = false

    public var onComplete: (() -> Void)?

    public init(onComplete: (() -> Void)? = nil) {
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar (Balanced Stepper & Back Navigation)
            headerBar

            // Center Stage Content Area (Clipped for Zero-Overdraw GPU Performance)
            ZStack {
                switch viewModel.currentStep {
                case 0:
                    WelcomeStepView()
                        .transition(stepTransition)
                case 1:
                    ContainersAndClustersStepView(viewModel: viewModel)
                        .transition(stepTransition)
                case 2:
                    PublicTunnelingStepView(viewModel: viewModel)
                        .transition(stepTransition)
                default:
                    ReadyStepView()
                        .transition(stepTransition)
                }
            }
            .padding(.horizontal, KumaSpacing.xxl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // Footer Navigation (Centered Primary CTA Button)
            footerCTA
        }
        .frame(width: 680, height: 500)
        .background(KumaColors.canvasBackground)
        .clipShape(RoundedRectangle(cornerRadius: KumaRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KumaRadius.xl, style: .continuous)
                .stroke(KumaColors.borderSubtle, lineWidth: 0.5)
        )
        .alert(
            "Invalid Binary Selection",
            isPresented: Binding(
                get: { viewModel.pathValidationError != nil },
                set: { if !$0 { viewModel.clearValidationError() } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.clearValidationError()
            }
        } message: {
            if let errorMsg = viewModel.pathValidationError {
                Text(errorMsg)
            }
        }
        .onAppear {
            viewModel.currentStep = 0
        }
        .task {
            // Instant zero-latency pre-scan in background while user reads Step 0
            await viewModel.scanDependenciesIfNeeded()
        }
    }

    private var stepAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82)
    }

    private var headerBar: some View {
        HStack(alignment: .center) {
            // Top Left: Back Icon Button
            ZStack(alignment: .leading) {
                if viewModel.canGoPrev {
                    Button {
                        guard !isTransitioning else { return }
                        isTransitioning = true
                        withAnimation(stepAnimation) {
                            viewModel.prevStep()
                        }
                        Task {
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            isTransitioning = false
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Previous Step")
                    .keyboardShortcut(.cancelAction)
                    .disabled(isTransitioning)
                }
            }
            .frame(width: 44, alignment: .leading)

            Spacer()

            // Top Center: Neutral Stepper Pills
            HStack(spacing: KumaSpacing.xs) {
                ForEach(0..<viewModel.totalSteps, id: \.self) { index in
                    Capsule()
                        .fill(
                            index == viewModel.currentStep
                            ? Color.primary.opacity(0.85)
                            : Color.primary.opacity(0.2)
                        )
                        .frame(width: index == viewModel.currentStep ? 20 : 6, height: 5)
                        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.78), value: viewModel.currentStep)
                }
            }

            Spacer()

            // Right spacer to keep stepper perfectly centered
            Color.clear
                .frame(width: 44, height: 28)
        }
        .frame(height: 44)
        .padding(.horizontal, KumaSpacing.lg)
        .padding(.top, KumaSpacing.md)
    }

    private var footerCTA: some View {
        VStack {
            KumaPrimaryButton(
                viewModel.canGoNext ? "Continue" : "Get Started"
            ) {
                guard !isTransitioning else { return }
                if viewModel.canGoNext {
                    isTransitioning = true
                    withAnimation(stepAnimation) {
                        viewModel.nextStep()
                    }
                    Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        isTransitioning = false
                    }
                } else {
                    onComplete?()
                    openWindow(id: "main-workspace")
                    dismissWindow(id: "onboarding")
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isTransitioning)
        }
        .padding(.bottom, KumaSpacing.xxl)
    }

    private var stepTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
}

#Preview {
    OnboardingWizardView()
}
