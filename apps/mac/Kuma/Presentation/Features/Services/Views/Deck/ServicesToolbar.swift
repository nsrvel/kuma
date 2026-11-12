import SwiftUI

extension ServicesDeckView {
    @ToolbarContentBuilder
    public func toolbarContent() -> some ToolbarContent {
        // 1. Add Service Button (+)
        ToolbarItem {
            Button {
                NotificationCenter.default.post(name: .kumaCreateServiceRequested, object: nil)
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add Service")
            .accessibilityHint("Opens creation sheet to add a new service")
            .help("Add new service")
        }

        // 2. View Mode Segmented Picker (Cards / Table)
        ToolbarItem {
            Picker("View Mode", selection: $viewModel.viewMode) {
                Image(systemName: "square.grid.2x2")
                    .accessibilityLabel("Grid View")
                    .tag(DeckViewMode.card)
                Image(systemName: "list.bullet")
                    .accessibilityLabel("Table View")
                    .tag(DeckViewMode.table)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Deck View Mode")
            .help("Switch between card and table view")
        }

        // 3. Filter Menu
        ToolbarItem {
            ServicesToolbarFilterMenu(viewModel: viewModel)
        }

        // 4. Sort Menu (Pure macOS HIG: Section + Native Radio Toggles)
        ToolbarItem {
            Menu {
                Section("Sort By") {
                    ForEach(ServiceSortOption.allCases, id: \.self) { sortOpt in
                        Toggle(sortOpt.rawValue, isOn: Binding(
                            get: { viewModel.sortBy == sortOpt },
                            set: { if $0 { viewModel.sortBy = sortOpt } }
                        ))
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuIndicator(.hidden)
            .accessibilityLabel("Sort Services")
            .accessibilityHint("Sorts services by name, status, or date")
            .help("Sort services")
        }

        // 5. Actions Ellipsis Menu (Start All, Stop All, Import, Export)
        ToolbarItem {
            ServicesToolbarActionsMenu(viewModel: viewModel)
        }

        // 6. Native Trailing Sidebar Toggle
        ToolbarItem {
            Button {
                viewModel.isInspectorPresented.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .accessibilityLabel(viewModel.isInspectorPresented ? "Hide detail panel" : "Show detail panel")
            .accessibilityHint("Toggles the service inspector. Shortcut: Command I.")
            .help(viewModel.isInspectorPresented ? "Hide detail panel (⌘I)" : "Show detail panel (⌘I)")
            .keyboardShortcut("i", modifiers: [.command])
        }
    }
}
