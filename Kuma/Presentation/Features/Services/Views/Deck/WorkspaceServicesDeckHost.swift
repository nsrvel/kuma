import SwiftUI

/// Keeps one `ServicesDeckViewModel` per workspace so sidebar filter switches do not reload the deck.
struct WorkspaceServicesDeckHost: View {
    let workspaceID: UUID
    let selectedSidebarID: UUID?
    @Bindable var sidebarViewModel: SidebarViewModel

    @State private var viewModel = ServicesDeckViewModel()
    @State private var deckActions: ServiceDeckActions?
    @Environment(ServiceStateStore.self) private var serviceStateStore

    private var isStarredOnly: Bool {
        selectedSidebarID == .stable("starred-services")
    }

    private var filterGroupID: UUID? {
        sidebarViewModel.groupIDForSelectedRow(selectedSidebarID)
    }

    var body: some View {
        Group {
            if let deckActions {
                ServicesDeckView(
                    workspaceID: workspaceID,
                    viewModel: viewModel,
                    deckActions: deckActions,
                    isStarredOnly: isStarredOnly,
                    filterGroupID: filterGroupID
                )
            } else {
                Color.clear
            }
        }
        .onAppear {
            deckActions = viewModel.makeDeckActions(workspaceID: workspaceID)
        }
        .task(id: workspaceID) {
            viewModel.stateStore = serviceStateStore
            deckActions = viewModel.makeDeckActions(workspaceID: workspaceID)
            syncSidebarFiltersToViewModel()
            await viewModel.loadWorkspaceAsync(workspaceID: workspaceID)
        }
        .onChange(of: selectedSidebarID) { _, _ in
            syncSidebarFiltersToViewModel()
        }
        .onChange(of: isStarredOnly) { _, newStarred in
            viewModel.isStarredOnly = newStarred
        }
        .onChange(of: filterGroupID) { _, newGroupID in
            viewModel.filterGroupID = newGroupID
        }
    }

    private func syncSidebarFiltersToViewModel() {
        viewModel.isStarredOnly = isStarredOnly
        viewModel.filterGroupID = filterGroupID
    }
}
