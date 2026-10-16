import SwiftUI

public enum ActivityLogDisplay {
    public static func formatTime(_ date: Date) -> String {
        ActivityLogFormatting.formatTime(date)
    }

    public static func message(from text: String, category: ActivityLogCategory) -> String {
        ActivityLogFormatting.displayMessage(from: text, category: category)
    }

    public static func foregroundColor(for category: ActivityLogCategory) -> Color {
        switch category {
        case .kuma, .health, .monitor, .raw:
            return Color(nsColor: .labelColor)
        case .failure:
            return KumaStatus.failedIndicator
        case .failureContinuation:
            return KumaStatus.failedIndicator.opacity(0.9)
        case .config:
            return KumaStatus.transitionalIndicator
        }
    }
}
