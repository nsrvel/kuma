import SwiftUI

// MARK: - TunnelEngineOption

public enum TunnelEngineOption: String, CaseIterable, Identifiable, Sendable {
    case cloudflare = "cloudflare"
    case ngrok = "ngrok"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cloudflare: return "Cloudflare Tunnel"
        case .ngrok:      return "Ngrok Tunnel"
        }
    }
}

// MARK: - TunnelSettingsView

/// Configuration view for Public Tunneling provider (Cloudflare Tunnel & Ngrok).
public struct TunnelSettingsView: View {
    @Binding public var tunnelType: TunnelEngineOption
    @Binding public var tunnelTargetUrl: String
    @Binding public var ngrokAuthToken: String

    public init(
        tunnelType: Binding<TunnelEngineOption>,
        tunnelTargetUrl: Binding<String>,
        ngrokAuthToken: Binding<String>
    ) {
        self._tunnelType = tunnelType
        self._tunnelTargetUrl = tunnelTargetUrl
        self._ngrokAuthToken = ngrokAuthToken
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            KumaRowPickerField(
                label: "Tunnel Engine",
                description: "Tunnel engine used to expose local services.",
                options: TunnelEngineOption.allCases,
                selection: $tunnelType,
                titleResolver: { $0.title }
            )

            Divider().opacity(0.3)

            KumaTextField(
                label: "Target URL or Port",
                value: $tunnelTargetUrl,
                placeholder: "http://localhost:3000"
            )

            if tunnelType == .ngrok {
                KumaSecureField(
                    label: "Ngrok Auth Token",
                    value: $ngrokAuthToken,
                    placeholder: "Uses ngrok config if empty"
                )
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var engine = TunnelEngineOption.cloudflare
        @State private var url = "http://localhost:3000"
        @State private var token = ""

        var body: some View {
            KumaFormSection(
                icon: "cloud.bolt.fill",
                title: "Public Tunnel"
            ) {
                TunnelSettingsView(
                    tunnelType: $engine,
                    tunnelTargetUrl: $url,
                    ngrokAuthToken: $token
                )
            }
            .padding()
            .frame(width: 500)
            .background(KumaColors.canvasBackground)
        }
    }
    return PreviewWrapper()
}
