import SwiftUI

// MARK: - SidebarEmptyPlaceholderRow

public struct SidebarEmptyPlaceholderRow: View {
    public let title: String
    public let indentLevel: Int

    public init(title: String, indentLevel: Int) {
        self.title = title
        self.indentLevel = indentLevel
    }

    public var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .italic()
                .foregroundStyle(Color.secondary.opacity(0.65))
            Spacer(minLength: 0)
        }
        .padding(.leading, KumaTheme.Sidebar.rowHorizontalPadding + (CGFloat(indentLevel) * KumaTheme.Sidebar.indentWidth))
        .padding(.trailing, KumaTheme.Sidebar.rowHorizontalPadding)
        .padding(.vertical, 3)
    }
}

#Preview {
    SidebarEmptyPlaceholderRow(title: "No services", indentLevel: 1)
        .frame(width: 220)
        .padding()
}
