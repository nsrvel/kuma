import SwiftUI

public struct KumaCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    public init(
        padding: CGFloat = KumaSpacing.md,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .background(KumaColors.surfaceBackground, in: RoundedRectangle(cornerRadius: KumaRadius.md, style: .continuous))
    }
}

#Preview {
    VStack(spacing: KumaSpacing.md) {
        KumaCard {
            HStack {
                Text("Card Item")
                    .font(KumaFont.heading)
                Spacer()
                Image(systemName: "chevron.right")
            }
        }

        KumaCard {
            Text("Static Card Container")
                .font(KumaFont.body)
        }
    }
    .padding()
    .frame(width: 350)
}
