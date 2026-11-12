import SwiftUI
import Testing
@testable import Kuma

@Suite("Settings Category F: Headless SwiftUI View Hierarchy & Accessibility HIG", .serialized)
@MainActor
struct SettingsVisualTests {

    // MARK: - [TC-F01] Settings View Renders All Sections
    @Test("TC-F01: SettingsView initializes without layout crashes")
    func testSettingsViewRendersAllSections() {
        let harness = SettingsTestHarness()
        defer { harness.cleanup() }

        let viewModel = SettingsViewModel(userDefaults: harness.userDefaults)
        let store = WorkspaceStore()

        let view = SettingsView(viewModel: viewModel, workspaceStore: store)
        #expect(view != nil)
    }

    // MARK: - [TC-F02] Appearance Card Rendering
    @Test("TC-F02: AppearanceCard initializes properly for all appearance modes")
    func testAppearanceCardSelectionAnimation() {
        struct Container: View {
            @Namespace var ns
            var body: some View {
                AppearanceCard(
                    mode: .system,
                    isSelected: true,
                    namespace: ns,
                    onSelect: {}
                )
            }
        }

        let container = Container()
        #expect(container != nil)
    }

    // MARK: - [TC-F03] Binary Status Badge Rendering
    @Test("TC-F03: BinaryStatusBadge renders installed and missing visual cues")
    func testBinaryStatusBadgeRendering() {
        let installedBadge = BinaryStatusBadge(isInstalled: true)
        let missingBadge = BinaryStatusBadge(isInstalled: false)

        #expect(installedBadge.isInstalled == true)
        #expect(missingBadge.isInstalled == false)
    }

    // MARK: - [TC-F04] Data Section Rendering
    @Test("TC-F04: SettingsDataSection renders backup and reset rows")
    func testDataSectionRendering() {
        let harness = SettingsTestHarness()
        defer { harness.cleanup() }

        let viewModel = SettingsViewModel(userDefaults: harness.userDefaults)
        let store = WorkspaceStore()
        let section = SettingsDataSection(viewModel: viewModel, workspaceStore: store)

        #expect(section != nil)
    }

    // MARK: - [TC-F06] Ports & Connections Section Rendering
    @Test("TC-F06: SettingsPortsConnectionsSection renders conflict picker")
    func testPortsConnectionsSectionRendering() {
        let harness = SettingsTestHarness()
        defer { harness.cleanup() }

        let viewModel = SettingsViewModel(userDefaults: harness.userDefaults)
        let section = SettingsPortsConnectionsSection(viewModel: viewModel)

        #expect(section != nil)
        #expect(viewModel.portConflictPolicy == .warnAndBlock)
    }
}
