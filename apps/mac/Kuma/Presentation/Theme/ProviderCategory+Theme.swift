import SwiftUI

extension ProviderCategory {
    // MARK: - SF Symbol Icon

    public var icon: String {
        switch self {
        case .docker:         return "shippingbox.fill"
        case .kubernetes:     return "network"
        case .podman:         return "cylinder.split.1x2.fill"
        case .shell:          return "terminal.fill"
        case .ssh:            return "server.rack"
        case .httpCheck:      return "heart.fill"
        case .tunnel:         return "cloud.bolt.fill"
        case .processMonitor: return "cpu.fill"
        }
    }

    // MARK: - Brand Color (Vibrant & Rich Palettes)

    public var color: Color {
        switch self {
        case .docker:         return Color(red: 0x25 / 255.0, green: 0xB1 / 255.0, blue: 0xE7 / 255.0) // #25B1E7 Docker Cyan-Blue
        case .kubernetes:     return Color(red: 0x30 / 255.0, green: 0x69 / 255.0, blue: 0xDD / 255.0) // #3069DD
        case .podman:         return Color(red: 0x89 / 255.0, green: 0x33 / 255.0, blue: 0xA0 / 255.0) // #8933A0
        case .shell:          return Color(red: 0x06 / 255.0, green: 0xAE / 255.0, blue: 0x01 / 255.0) // #06AE01
        case .ssh:            return Color(red: 0x47 / 255.0, green: 0x55 / 255.0, blue: 0x69 / 255.0) // #475569
        case .httpCheck:      return Color(red: 0x86 / 255.0, green: 0xBE / 255.0, blue: 0x3C / 255.0) // #86BE3C Medical Leaf Green
        case .tunnel:         return Color(red: 0xED / 255.0, green: 0x7D / 255.0, blue: 0x20 / 255.0) // #ED7D20
        case .processMonitor: return Color(red: 0xCE / 255.0, green: 0x16 / 255.0, blue: 0x21 / 255.0) // #CE1621
        }
    }

    /// Harmonious, smooth diagonal gradient (Soft shaded topLeading ➔ Vibrant rich bottomTrailing)
    public var gradient: LinearGradient {
        switch self {
        case .docker:
            return LinearGradient(
                colors: [Color(red: 0x14 / 255.0, green: 0x82 / 255.0, blue: 0xCA / 255.0), Color(red: 0x25 / 255.0, green: 0xB1 / 255.0, blue: 0xE7 / 255.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .kubernetes:
            return LinearGradient(
                colors: [Color(red: 0x24 / 255.0, green: 0x55 / 255.0, blue: 0xBD / 255.0), Color(red: 0x30 / 255.0, green: 0x69 / 255.0, blue: 0xDD / 255.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .podman:
            return LinearGradient(
                colors: [Color(red: 0x6E / 255.0, green: 0x24 / 255.0, blue: 0x82 / 255.0), Color(red: 0x89 / 255.0, green: 0x33 / 255.0, blue: 0xA0 / 255.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .shell:
            return LinearGradient(
                colors: [Color(red: 0x04 / 255.0, green: 0x8A / 255.0, blue: 0x01 / 255.0), Color(red: 0x06 / 255.0, green: 0xAE / 255.0, blue: 0x01 / 255.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .ssh:
            return LinearGradient(
                colors: [Color(red: 0x33 / 255.0, green: 0x3F / 255.0, blue: 0x52 / 255.0), Color(red: 0x47 / 255.0, green: 0x55 / 255.0, blue: 0x69 / 255.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .httpCheck:
            return LinearGradient(
                colors: [Color(red: 0x6B / 255.0, green: 0x9E / 255.0, blue: 0x2A / 255.0), Color(red: 0x86 / 255.0, green: 0xBE / 255.0, blue: 0x3C / 255.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .tunnel:
            return LinearGradient(
                colors: [Color(red: 0xC4 / 255.0, green: 0x5E / 255.0, blue: 0x10 / 255.0), Color(red: 0xED / 255.0, green: 0x7D / 255.0, blue: 0x20 / 255.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .processMonitor:
            return LinearGradient(
                colors: [Color(red: 0xA6 / 255.0, green: 0x0F / 255.0, blue: 0x18 / 255.0), Color(red: 0xCE / 255.0, green: 0x16 / 255.0, blue: 0x21 / 255.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
