import SwiftUI

public struct ReadyStepView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: KumaSpacing.xl) {
            // Minimal Checkmark Icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(.green.opacity(0.85))

            // Header Typography
            VStack(spacing: KumaSpacing.xs) {
                Text("You're all set.")
                    .font(KumaFont.stepTitle)
                    .foregroundStyle(.primary)

                Text("Kuma is ready to orchestrate your services.")
                    .font(KumaFont.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ReadyStepView()
        .frame(width: 680, height: 500)
        .background(KumaColors.canvasBackground)
}
