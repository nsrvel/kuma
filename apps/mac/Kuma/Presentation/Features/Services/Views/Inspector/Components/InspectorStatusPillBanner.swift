import SwiftUI

public struct InspectorStatusPillBanner: View {
    public let title: String
    public let subtitle: String
    public let tone: Color
    public let showsOrbit: Bool
    public let showsGlow: Bool
    public let washStrength: Double
    public var onViewLogs: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breatheHigh = false

    public init(
        title: String,
        subtitle: String,
        tone: Color,
        showsOrbit: Bool = false,
        showsGlow: Bool = false,
        washStrength: Double = 0.10,
        onViewLogs: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.tone = tone
        self.showsOrbit = showsOrbit
        self.showsGlow = showsGlow
        self.washStrength = washStrength
        self.onViewLogs = onViewLogs
    }

    private var effectiveWashOpacity: Double {
        guard washStrength > 0 else { return 0 }
        if showsOrbit && !reduceMotion {
            return breatheHigh ? 0.13 : 0.07
        }
        return washStrength
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 10) {
            StatusPillLeadingIndicator(color: tone, showsOrbit: showsOrbit, showsGlow: showsGlow)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if let onViewLogs {
                liveLogsButton(action: onViewLogs)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            KumaToneWashBackground(
                tone: tone,
                washOpacity: effectiveWashOpacity,
                strokeOpacity: 0.18
            )
        }
        .animation(.smooth(duration: 0.3), value: effectiveWashOpacity)
        .onAppear { startBreathingIfNeeded() }
        .onChange(of: showsOrbit) { _, _ in startBreathingIfNeeded() }
        .onChange(of: reduceMotion) { _, _ in startBreathingIfNeeded() }
    }

    private func startBreathingIfNeeded() {
        guard showsOrbit, !reduceMotion else {
            breatheHigh = false
            return
        }
        breatheHigh = false
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            breatheHigh = true
        }
    }

    private func liveLogsButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 9))
                Text("Live Logs")
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(KumaUIID.inspectorLiveLogsButton)
        .help("Open real-time console logs")
    }
}
