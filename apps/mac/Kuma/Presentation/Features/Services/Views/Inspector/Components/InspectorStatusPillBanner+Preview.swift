import SwiftUI

#Preview("Inspector status banners") {
    VStack(spacing: 8) {
        InspectorStatusPillBanner(
            title: "Running",
            subtitle: "Settings are read-only while active.",
            tone: KumaStatus.runningIndicator,
            showsGlow: true
        )
        InspectorStatusPillBanner(
            title: "Starting…",
            subtitle: "Bringing the runner online.",
            tone: KumaStatus.transitionalIndicator,
            showsOrbit: true
        )
        InspectorStatusPillBanner(
            title: "Crashed",
            subtitle: "Open Live Logs for details.",
            tone: KumaStatus.failedIndicator,
            washStrength: 0.12
        )
        InspectorStatusPillBanner(
            title: "Stopped",
            subtitle: "You can edit all settings.",
            tone: KumaStatus.idleIndicator
        )
        InspectorStatusPillBanner(
            title: "Disabled",
            subtitle: "Turn on in Options to run or edit.",
            tone: KumaStatus.disabledIndicator,
            washStrength: 0
        )
    }
    .padding()
    .frame(width: 380)
}
