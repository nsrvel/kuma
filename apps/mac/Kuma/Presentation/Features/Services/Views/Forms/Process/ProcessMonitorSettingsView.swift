import SwiftUI

// MARK: - ProcessMonitorSettingsView

/// Configuration view for Process Monitor provider (Process Name & Polling Interval Dropdown).
public struct ProcessMonitorSettingsView: View {
    @Binding public var monitorProcessName: String
    @Binding public var monitorInterval: HealthCheckIntervalOption

    public init(
        monitorProcessName: Binding<String>,
        monitorInterval: Binding<HealthCheckIntervalOption>
    ) {
        self._monitorProcessName = monitorProcessName
        self._monitorInterval = monitorInterval
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            KumaTextField(
                label: "Process Name",
                value: $monitorProcessName,
                placeholder: "redis-server"
            )

            KumaRowPickerField(
                label: "Polling Interval",
                description: "Frequency of background process checks.",
                options: HealthCheckIntervalOption.allCases,
                selection: $monitorInterval,
                titleResolver: { $0.title }
            )
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var name = "postgres"
        @State private var interval = HealthCheckIntervalOption.fast

        var body: some View {
            KumaFormSection(
                icon: "cpu.fill",
                title: "Process Monitor"
            ) {
                ProcessMonitorSettingsView(
                    monitorProcessName: $name,
                    monitorInterval: $interval
                )
            }
            .padding()
            .frame(width: 500)
            .background(KumaColors.canvasBackground)
        }
    }
    return PreviewWrapper()
}
