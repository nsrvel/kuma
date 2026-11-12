import SwiftUI

public struct ImportPortsBadgeView: View {
    public let portMappings: [DataPortService.ExportPortMapping]
    public let maxVisible: Int

    public init(portMappings: [DataPortService.ExportPortMapping], maxVisible: Int = 2) {
        self.portMappings = portMappings
        self.maxVisible = maxVisible
    }

    public var body: some View {
        if portMappings.isEmpty {
            Text("—")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        } else {
            Text(summaryText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(fullSummaryText)
        }
    }

    private var summaryText: String {
        Self.summary(portMappings: portMappings, maxVisible: maxVisible)
    }

    private var fullSummaryText: String {
        Self.summary(portMappings: portMappings, maxVisible: portMappings.count)
    }

    /// ponytail: comma-joined host (local) ports only; `+N` when truncated.
    static func summary(
        portMappings: [DataPortService.ExportPortMapping],
        maxVisible: Int
    ) -> String {
        guard !portMappings.isEmpty else { return "—" }
        let visible = portMappings.prefix(max(0, maxVisible))
        var parts = visible.map { KumaPortFormatting.plain($0.localPort) }
        if portMappings.count > maxVisible {
            parts.append("+\(portMappings.count - maxVisible)")
        }
        return parts.joined(separator: ", ")
    }
}
