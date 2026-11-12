import SwiftUI

#Preview {
    struct PreviewWrapper: View {
        @State private var vm = KubeConfigViewModel()

        var body: some View {
            KubeConfigInlineEditorView(
                viewModel: vm,
                onDismiss: {},
                onSaveSuccess: {}
            )
            .padding()
            .frame(width: 420)
            .onAppear {
                vm.showInlineNewConfigForm = true
            }
        }
    }
    return PreviewWrapper()
}
