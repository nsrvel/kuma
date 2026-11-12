import SwiftUI

/// System activity log for Service Inspector (read-only buffer).
public struct InspectorLiveConsoleView: View {
    public let serviceID: UUID
    public let isRunning: Bool
    public var lastFailure: String?
    public var configurationMessages: [String]

    @State private var session = LiveLogSession.shared

    public init(
        serviceID: UUID,
        isRunning: Bool,
        lastFailure: String? = nil,
        configurationMessages: [String] = []
    ) {
        self.serviceID = serviceID
        self.isRunning = isRunning
        self.lastFailure = lastFailure
        self.configurationMessages = configurationMessages
    }

    private var logSnapshot: LiveLogSession.ServiceSnapshot {
        session.snapshot(for: serviceID)
    }

    public var body: some View {
        let snapshot = logSnapshot
        Group {
            if snapshot.lines.isEmpty {
                VStack(spacing: 8) {
                    Text("No activity yet")
                        .font(KumaFont.title3)
                    Text(isRunning
                         ? "System messages for this run will appear here."
                         : "Start the service to see activity, or open after a run to review the last log.")
                        .font(KumaFont.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(KumaSpacing.lg)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(snapshot.lines) { line in
                            SystemActivityLogRow(line: line)
                        }
                    }
                    .padding(.horizontal, KumaSpacing.lg)
                    .padding(.vertical, KumaSpacing.sm)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            session.markRecentlyUsed(serviceID: serviceID)
            session.syncBannerContext(
                serviceID: serviceID,
                lastFailure: lastFailure,
                configurationMessages: configurationMessages
            )
        }
        .onChange(of: lastFailure) { _, newValue in
            guard let newValue else { return }
            Task { @MainActor in
                session.recordBannerFailure(serviceID: serviceID, message: newValue)
            }
        }
        .onChange(of: configurationMessages) { _, newValue in
            Task { @MainActor in
                session.recordConfigurationIssues(serviceID: serviceID, messages: newValue)
            }
        }
    }
}
