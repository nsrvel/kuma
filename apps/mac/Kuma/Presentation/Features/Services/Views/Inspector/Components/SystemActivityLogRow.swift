import SwiftUI

struct SystemActivityLogRow: View {
    let line: LiveLogSession.LiveLogLine

    private var displayMessage: String {
        ActivityLogDisplay.message(from: line.text, category: line.category)
    }

    private var messageColor: Color {
        ActivityLogDisplay.foregroundColor(for: line.category)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(ActivityLogDisplay.formatTime(line.timestamp))
                .font(KumaLogFont.logTimestamp)
                .monospacedDigit()
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .frame(width: 50, alignment: .leading)

            Text(displayMessage)
                .font(KumaLogFont.logMessage)
                .foregroundStyle(messageColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
    }
}
