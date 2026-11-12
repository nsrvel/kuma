import SwiftUI

// MARK: - HealthCheckIntervalOption

public enum HealthCheckIntervalOption: Int, CaseIterable, Identifiable, Sendable {
    case fast = 5
    case standard = 10
    case relaxed = 30
    case slow = 60

    public var id: Int { rawValue }

    public var title: String {
        "\(rawValue)s"
    }
}

// MARK: - HealthCheckSettingsView

/// Configuration view for HTTP Health Check provider (Target URL & Polling Interval Dropdown).
public struct HealthCheckSettingsView: View {
    @Binding public var httpCheckUrl: String
    @Binding public var checkInterval: HealthCheckIntervalOption

    public init(
        httpCheckUrl: Binding<String>,
        checkInterval: Binding<HealthCheckIntervalOption>
    ) {
        self._httpCheckUrl = httpCheckUrl
        self._checkInterval = checkInterval
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            KumaTextField(
                label: "Target URL",
                value: $httpCheckUrl,
                placeholder: "https://api.example.com/health"
            )

            KumaRowPickerField(
                label: "Polling Interval",
                description: "Frequency of health check requests.",
                options: HealthCheckIntervalOption.allCases,
                selection: $checkInterval,
                titleResolver: { $0.title }
            )
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var url = "http://localhost:8080/healthz"
        @State private var interval = HealthCheckIntervalOption.standard

        var body: some View {
            KumaFormSection(
                icon: "heart.text.square.fill",
                title: "Health Check"
            ) {
                HealthCheckSettingsView(
                    httpCheckUrl: $url,
                    checkInterval: $interval
                )
            }
            .padding()
            .frame(width: 500)
            .background(KumaColors.canvasBackground)
        }
    }
    return PreviewWrapper()
}
