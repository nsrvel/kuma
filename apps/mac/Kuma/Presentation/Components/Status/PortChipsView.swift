import SwiftUI

public struct PortChipsView: View {
    public let ports: [Int]
    public var maxVisible: Int?

    public init(ports: [Int], maxVisible: Int? = nil, limit: Int? = nil) {
        self.ports = ports
        self.maxVisible = maxVisible ?? limit
    }

    public var body: some View {
        let limit = maxVisible ?? ports.count
        let overflow = max(0, ports.count - limit)

        HStack(spacing: 6) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)

            HStack(spacing: 4) {
                ForEach(ports.prefix(limit), id: \.self) { port in
                    PortChipLabel(port: port)
                }
                if overflow > 0 {
                    Text(verbatim: "+\(overflow)")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 3)
                        .fixedSize()
                }
            }
        }
    }
}

private struct PortChipLabel: View {
    let port: Int

    var body: some View {
        let label = KumaPortFormatting.plain(port)
        Text(verbatim: label)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
            }
            .fixedSize()
            .accessibilityLabel("Port \(label)")
            .accessibilityIdentifier(KumaUIID.servicePortChip(port))
    }
}
