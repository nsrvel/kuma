import SwiftUI

public struct SidebarFooterView: View {
    @Bindable var viewModel: SidebarViewModel

    public init(viewModel: SidebarViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            KumaDivider(opacity: 0.08, verticalPadding: 0, horizontalPadding: 8)

            HStack(spacing: 8) {
                SidebarFooterButton(
                    icon: "gear",
                    tooltip: "Settings (⌘,)",
                    isSelected: viewModel.selectedID == .stable("settings")
                ) {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                        viewModel.selectedID = .stable("settings")
                    }
                }

                SidebarFooterButton(icon: "questionmark.circle", tooltip: "Help") {
                    NSWorkspace.shared.open(KumaLinks.repository)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color.clear)
    }
}

#Preview {
    SidebarFooterView(viewModel: SidebarViewModel.makeDefault())
        .frame(width: 220)
}
