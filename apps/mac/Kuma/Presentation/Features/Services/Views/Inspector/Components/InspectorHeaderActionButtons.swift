import SwiftUI

public struct InspectorHeaderActionButton: View {
    public let runtime: ServiceRuntimeState
    public var isStartDisabled: Bool = false
    public let onToggle: () -> Void

    public init(
        runtime: ServiceRuntimeState,
        isStartDisabled: Bool = false,
        onToggle: @escaping () -> Void
    ) {
        self.runtime = runtime
        self.isStartDisabled = isStartDisabled
        self.onToggle = onToggle
    }

    public var body: some View {
        let showsStop = showsStopChrome(for: runtime.status)
        let showsBusyIndicator = runtime.status == .starting
            || runtime.status == .stopping
            || runtime.status == .reconnecting
        let blocksStart = runtime.isLoading
            || runtime.status == .starting
            || runtime.status == .stopping
            || runtime.status == .reconnecting
        let startBlocked = !showsStop && isStartDisabled
        let interactionBlocked = showsStop ? false : (blocksStart || startBlocked)

        Button {
            guard !interactionBlocked else { return }
            KumaHapticManager.shared.tap()
            onToggle()
        } label: {
            HStack(spacing: 5) {
                if showsBusyIndicator {
                    KumaActivityIndicator(size: 11, color: .white, lineWidth: 1.5)
                }
                Text(showsStop ? "Stop" : "Start")
                    .frame(minWidth: 34, alignment: .center)
                    .contentTransition(.interpolate)
            }
        }
        .buttonStyle(KumaPrimaryButtonStyle.inspectorToggle(isRunning: showsStop))
        .opacity(startBlocked ? 0.45 : 1)
        .allowsHitTesting(!interactionBlocked)
        .help(startBlocked ? "Fix configuration issues before starting" : "")
        .padding(.trailing, 8)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .animation(showsBusyIndicator ? nil : .easeInOut(duration: 0.18), value: showsStop)
    }

    private func showsStopChrome(for status: ServiceState) -> Bool {
        switch status {
        case .running, .starting, .stopping, .reconnecting:
            return true
        case .stopped, .crashed:
            return false
        }
    }
}
