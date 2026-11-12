import SwiftUI

public struct ImportPortMappingsSectionView: View {
    public let portMappings: [DataPortService.ExportPortMapping]

    public init(portMappings: [DataPortService.ExportPortMapping]) {
        self.portMappings = portMappings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KumaSpacing.sm) {
            HStack(spacing: KumaSpacing.xs) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text("PORT MAPPINGS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, KumaSpacing.xs)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(portMappings.enumerated()), id: \.element.id) { index, port in
                    if index > 0 {
                        Divider()
                            .padding(.vertical, 3)
                            .opacity(0.4)
                    }

                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)

                        Text(verbatim: "localhost:\(KumaPortFormatting.plain(port.localPort))")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.primary)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)

                        Text(verbatim: "\(KumaPortFormatting.plain(port.remotePort))/TCP")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Spacer()
                    }
                    .padding(.vertical, 3)
                }
            }
            .padding(.horizontal, KumaSpacing.md)
            .padding(.vertical, KumaSpacing.sm)
            .background(KumaColors.surfaceBackground, in: RoundedRectangle(cornerRadius: KumaRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: KumaRadius.md, style: .continuous)
                    .strokeBorder(KumaColors.borderSubtle.opacity(0.5), lineWidth: 0.5)
            }
        }
    }
}
