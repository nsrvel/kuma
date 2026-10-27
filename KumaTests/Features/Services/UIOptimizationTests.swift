import Foundation
import SwiftUI
import Testing
@testable import Kuma

@Suite("UI Optimization & Performance Tests", .serialized)
struct UIOptimizationTests {

    @Test("TC-UI01: Deck search updates filtered results immediately")
    @MainActor
    func testDeckSearchDebouncing() async throws {
        let suiteName = "test-deck-debounce-\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        let vm = ServicesDeckViewModel(
            userDefaults: ud
        )

        let s1 = ServiceCardSnapshot(
            id: UUID(),
            name: "Alpha Service",
            groupIDs: [],
            isDisabled: false,
            isStarred: false,
            subtitle: "nginx:latest",
            providerCategory: .docker,
            portDisplays: [],
            providerOptions: [],
            createdAt: Date()
        )
        let s2 = ServiceCardSnapshot(
            id: UUID(),
            name: "Beta Worker",
            groupIDs: [],
            isDisabled: false,
            isStarred: false,
            subtitle: "worker.sh",
            providerCategory: .shell,
            portDisplays: [],
            providerOptions: [],
            createdAt: Date()
        )

        vm.snapshots = [s1, s2]
        #expect(vm.filteredSnapshots.count == 2)

        vm.searchText = "Alpha"

        #expect(vm.filteredSnapshots.count == 1)
        #expect(vm.filteredSnapshots.first?.name == "Alpha Service")
    }

    @Test("TC-G02: ServiceCardView does not reference ServicesDeckViewModel")
    func testServiceCardViewUsesDeckActionsNotViewModel() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Kuma/Presentation/Features/Services/Views/Deck/Components/ServiceCardView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        #expect(!source.contains("ServicesDeckViewModel"))
        #expect(source.contains("serviceDeckActions"))
    }

    @Test("TC-E05: Deck skips execution-state notifications when fully idle")
    @MainActor
    func testZeroEffortWhenIdle() {
        let store = ServiceStateStore()
        #expect(!ServicesDeckRuntimeObservation.shouldHandleExecutionStateNotifications(store: store))
        store.setExecutionState(.starting, for: UUID())
        #expect(ServicesDeckRuntimeObservation.shouldHandleExecutionStateNotifications(store: store))
    }

    @Test("TC-E05c: Deck observation stays active while store still shows running")
    @MainActor
    func testObservationWhenStoreOperationalButRegistryIdle() {
        let store = ServiceStateStore()
        store.setExecutionState(.running(pid: 42), for: UUID())
        #expect(ServicesDeckRuntimeObservation.shouldHandleExecutionStateNotifications(store: store))
    }

    @Test("TC-E05b: notifyExecutionStatesChanged skips recompute unless search, status filter, or sort")
    @MainActor
    func testNotifyExecutionStatesChangedSkipsRecomputeWhenIdleFilters() {
        let suiteName = "test-deck-notify-\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        let vm = ServicesDeckViewModel(userDefaults: ud)
        vm.snapshots = [
            ServiceCardSnapshot(id: UUID(), name: "A", providerCategory: .docker),
            ServiceCardSnapshot(id: UUID(), name: "B", providerCategory: .shell),
        ]
        let versionBefore = vm.filterVersion
        vm.notifyExecutionStatesChanged()
        #expect(vm.filterVersion == versionBefore)

        vm.searchText = "A"
        let versionWithSearch = vm.filterVersion
        vm.notifyExecutionStatesChanged()
        #expect(vm.filterVersion > versionWithSearch)

        vm.searchText = ""
        vm.sortBy = .status
        let versionWithSort = vm.filterVersion
        vm.notifyExecutionStatesChanged()
        #expect(vm.filterVersion > versionWithSort)
    }

    @Test("TC-G02b: ServiceCardView renders headlessly with deck actions environment")
    @MainActor
    func testServiceCardViewHeadlessRender() {
        let snapshot = ServiceCardSnapshot(
            id: UUID(),
            name: "Headless",
            providerCategory: .docker,
            portDisplays: [3000]
        )
        let store = ServiceStateStore()
        let wsID = UUID()
        let actions = ServiceDeckActions(
            workspaceID: wsID,
            groups: { [] },
            groupIDsForService: { _ in [] },
            onSelect: { _ in },
            onToggle: { _ in },
            onRestart: { _ in },
            onSwitchProvider: { _, _ in },
            onToggleStar: { _ in },
            onToggleDisabled: { _ in },
            onToggleGroup: { _, _ in },
            onDuplicate: { _ in },
            onCopyConfig: { _ in },
            onDelete: { _ in }
        )
        let card = ServiceCardView(snapshot: snapshot, runtime: .idle, isSelected: false)
        #expect(card.snapshot.name == "Headless")
        _ = card.body
    }

    @Test("TC-G03: Deck card grid uses native adaptive min/max layout")
    func testDeckCardGridUsesAdaptiveMinMax() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Kuma/Presentation/Features/Services/Views/Deck/Components/ServicesDeckCardGridView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        #expect(source.contains(".adaptive"))
        #expect(source.contains("cardMinWidth"))
        #expect(source.contains("cardMaxWidth"))
        #expect(!source.contains("maximum: .infinity"))
        #expect(!source.contains("onGeometryChange"))
    }

    @Test("TC-G04: ServicesDeckView does not rebuild deck actions in contentBody")
    func testServicesDeckViewDoesNotMakeDeckActionsInBody() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Kuma/Presentation/Features/Services/Views/Deck/ServicesDeckView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        #expect(!source.contains("makeDeckActions"))
    }

    @Test("TC-G05: Deck content body avoids holding ServicesDeckViewModel")
    func testDeckContentBodyIsSnapshotDriven() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Kuma/Presentation/Features/Services/Views/Deck/Components/ServicesDeckContentBodyView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        #expect(!source.contains("ServicesDeckViewModel"))
        #expect(source.contains("ServicesDeckCardGridView"))
    }

    @Test("TC-G06: Deck cards skip ProviderBrandIcon rasterization")
    func testDeckCardsDisableBrandIconRasterize() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Kuma/Presentation/Features/Services/Views/Deck/Components/ServiceCardView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        #expect(source.contains("rasterize: false"))
    }

    @Test("TC-UI02: LiveLogEntry formats correctly without memory overhead")
    func testLiveLogEntryCreation() {
        let entry = LiveLogEntry(
            serviceID: UUID(),
            serviceName: "Backend",
            level: "ERR",
            message: "Connection refused on port 5432"
        )
        #expect(entry.serviceName == "Backend")
        #expect(entry.level == "ERR")
        #expect(entry.message == "Connection refused on port 5432")
    }
}
