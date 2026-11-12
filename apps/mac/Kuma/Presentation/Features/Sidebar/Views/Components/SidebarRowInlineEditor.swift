import SwiftUI

public struct SidebarRowInlineEditor: View {
    public let node: SidebarNode
    public let indentLevel: Int
    public let onCommitRename: (String) -> Void

    @State private var draftTitle: String = ""
    @FocusState private var isTextFieldFocused: Bool

    public init(
        node: SidebarNode,
        indentLevel: Int,
        onCommitRename: @escaping (String) -> Void
    ) {
        self.node = node
        self.indentLevel = indentLevel
        self.onCommitRename = onCommitRename
    }

    public var body: some View {
        HStack(spacing: 0) {
            if indentLevel > 0 {
                Spacer().frame(width: CGFloat(indentLevel) * KumaTheme.Sidebar.indentWidth)
            }

            if !node.isSpecialHeader {
                SidebarRowIcon(icon: node.icon)
                    .frame(width: 18, height: 18)
                    .padding(.trailing, 8)
            }

            TextField("Group Name", text: $draftTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular))
                .focused($isTextFieldFocused)
                .onAppear {
                    draftTitle = node.title
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isTextFieldFocused = true
                    }
                }
                .onChange(of: node.title) { _, newTitle in
                    draftTitle = newTitle
                }
                .onChange(of: isTextFieldFocused) { _, focused in
                    if !focused {
                        onCommitRename(draftTitle)
                    }
                }
                .onSubmit {
                    onCommitRename(draftTitle)
                }
                .onExitCommand {
                    onCommitRename(node.title)
                }

            Spacer(minLength: 0)
        }
        .padding(.vertical, node.isSpecialHeader ? 6 : KumaTheme.Sidebar.rowVerticalPadding)
        .padding(.horizontal, KumaTheme.Sidebar.rowHorizontalPadding)
    }
}
