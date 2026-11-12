import SwiftUI

public struct KumaDivider: View {
    private let opacity: Double
    private let verticalPadding: CGFloat
    private let horizontalPadding: CGFloat

    public init(
        opacity: Double = 0.08,
        verticalPadding: CGFloat = 0,
        horizontalPadding: CGFloat = 0
    ) {
        self.opacity = opacity
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
    }

    public var body: some View {
        VStack(spacing: 0) {
            if verticalPadding > 0 {
                Spacer().frame(height: verticalPadding)
            }
            Rectangle()
                .fill(Color.primary.opacity(opacity))
                .frame(height: 1)
                .padding(.horizontal, horizontalPadding)
            if verticalPadding > 0 {
                Spacer().frame(height: verticalPadding)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        Text("Top Item")
        KumaDivider()
        Text("Bottom Item")
    }
    .padding()
    .frame(width: 250)
}
