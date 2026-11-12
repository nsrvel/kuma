import SwiftUI

public struct ImportPreviewHeaderView: View {
    public let title: String
    public let subtitle: String
    public let searchPrompt: String
    @Binding public var searchText: String

    public init(
        title: String,
        subtitle: String,
        searchPrompt: String = "Search services",
        searchText: Binding<String>
    ) {
        self.title = title
        self.subtitle = subtitle
        self.searchPrompt = searchPrompt
        self._searchText = searchText
    }

    public var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.gradient)
                    .frame(width: 36, height: 36)
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            KumaSearchField(text: $searchText, prompt: searchPrompt)
                .frame(width: 180, height: 24)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
