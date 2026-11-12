import SwiftUI

public struct ServicesToolbarFilterMenu: View {
    @Bindable var viewModel: ServicesDeckViewModel

    public var body: some View {
        Menu {
            Section("Status") {
                Toggle("Running", isOn: Binding(
                    get: { viewModel.selectedStatuses.contains(.running) },
                    set: { _ in toggleStatusFilter(.running) }
                ))

                Toggle("Stopped", isOn: Binding(
                    get: { viewModel.selectedStatuses.contains(.stopped) },
                    set: { _ in toggleStatusFilter(.stopped) }
                ))

                Toggle("Crashed", isOn: Binding(
                    get: { viewModel.selectedStatuses.contains(.crashed) },
                    set: { _ in toggleStatusFilter(.crashed) }
                ))

                Toggle("Disabled", isOn: Binding(
                    get: { viewModel.selectedStatuses.contains(.disabled) },
                    set: { _ in toggleStatusFilter(.disabled) }
                ))
            }

            Section("Provider") {
                ForEach(ProviderCategory.allCases, id: \.self) { prov in
                    Toggle(prov.sidebarLabel, isOn: Binding(
                        get: { viewModel.selectedProviders.contains(prov) },
                        set: { _ in toggleProviderFilter(prov) }
                    ))
                }
            }

            if !viewModel.selectedStatuses.isEmpty || !viewModel.selectedProviders.isEmpty {
                Divider()

                Button("Reset Filters") {
                    viewModel.selectedStatuses.removeAll()
                    viewModel.selectedProviders.removeAll()
                }
            }
        } label: {
            Image(systemName: (!viewModel.selectedStatuses.isEmpty || !viewModel.selectedProviders.isEmpty) ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Filter Services")
        .accessibilityHint("Filters services by status or provider type")
        .help("Filter services")
    }

    private func toggleStatusFilter(_ state: ServiceStatusFilterOption) {
        if viewModel.selectedStatuses.contains(state) {
            viewModel.selectedStatuses.remove(state)
        } else {
            viewModel.selectedStatuses.insert(state)
        }
    }

    private func toggleProviderFilter(_ prov: ProviderCategory) {
        if viewModel.selectedProviders.contains(prov) {
            viewModel.selectedProviders.remove(prov)
        } else {
            viewModel.selectedProviders.insert(prov)
        }
    }
}

public struct ServicesToolbarActionsMenu: View {
    @Bindable var viewModel: ServicesDeckViewModel

    public var body: some View {
        Menu {
            Button {
                NotificationCenter.default.post(name: .kumaCreateServiceRequested, object: nil)
            } label: {
                Label("Add New Service", systemImage: "plus")
            }

            Button {
                viewModel.startAllServices()
            } label: {
                Label("Start All", systemImage: "play.fill")
            }
            .disabled(!viewModel.canStartAll)

            Button {
                viewModel.stopAllServices()
            } label: {
                Label("Stop All", systemImage: "stop.fill")
            }
            .disabled(!viewModel.canStopAll)

            Divider()

            Button {
                NotificationCenter.default.post(name: .kumaImportWorkspace, object: nil)
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }

            Button {
                NotificationCenter.default.post(name: .kumaExportWorkspace, object: nil)
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("More Workspace Actions")
        .accessibilityHint("Offers bulk actions, import and export options")
        .help("More actions")
    }
}
