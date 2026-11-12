import SwiftUI
import UniformTypeIdentifiers

public struct ServicesDeckView: View {
    public let workspaceID: UUID
    public let deckActions: ServiceDeckActions
    public let isStarredOnly: Bool
    public let filterGroupID: UUID?

    @Bindable var viewModel: ServicesDeckViewModel
    @State var pendingImportBackup: DataPortService.KumaBackup? = nil
    @State var pendingImportFileName: String = ""
    @State var alertMessage: String? = nil
    @State var isSearching: Bool = false

    @Environment(WorkspaceStore.self) var workspaceStore
    @Environment(ServiceStateStore.self) var serviceStateStore

    public init(
        workspaceID: UUID,
        viewModel: ServicesDeckViewModel,
        deckActions: ServiceDeckActions,
        isStarredOnly: Bool = false,
        filterGroupID: UUID? = nil
    ) {
        self.workspaceID = workspaceID
        self.viewModel = viewModel
        self.deckActions = deckActions
        self.isStarredOnly = isStarredOnly
        self.filterGroupID = filterGroupID
    }

    public var body: some View {
        applyDeckNotificationHandlers(to: mainDeckContent, workspaceID: workspaceID)
    }

    @ViewBuilder
    private var mainDeckContent: some View {
        applyDeckChrome(to:
            VStack(spacing: 0) {
                contentBody
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(isStarredOnly ? "Starred Services" : "Services")
            .searchable(text: $viewModel.searchText, isPresented: $isSearching, placement: .toolbar, prompt: "Search services")
            .toolbar {
                toolbarContent()
            }
        )
    }

    private var contentBody: some View {
        ServicesDeckContentBodyView(
            hasInitialLoaded: viewModel.hasInitialLoaded,
            allSnapshotsEmpty: viewModel.snapshots.isEmpty,
            filteredSnapshots: viewModel.filteredSnapshots,
            filterVersion: viewModel.filterVersion,
            selectedServiceID: viewModel.selectedServiceID,
            viewMode: viewModel.viewMode,
            isStarredOnly: isStarredOnly,
            deckActions: deckActions
        )
        .environment(\.serviceDeckActions, deckActions)
    }
}

#Preview {
    WorkspaceServicesDeckHost(
        workspaceID: UUID(),
        selectedSidebarID: .stable("all-services"),
        sidebarViewModel: SidebarViewModel.makeDefault()
    )
    .frame(width: 900, height: 650)
}
