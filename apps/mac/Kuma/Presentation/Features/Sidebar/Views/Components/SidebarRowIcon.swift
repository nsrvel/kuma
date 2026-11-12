import SwiftUI

public struct SidebarRowIcon: View {
    public let icon: SidebarIcon

    public init(icon: SidebarIcon) {
        self.icon = icon
    }

    public var body: some View {
        switch icon {
        case .system(let name):
            if !name.isEmpty {
                Image(systemName: name)
                    .imageScale(.medium)
                    .symbolRenderingMode(.hierarchical)
            }
        case .asset(let name):
            if !name.isEmpty {
                Image(name)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
    }
}
