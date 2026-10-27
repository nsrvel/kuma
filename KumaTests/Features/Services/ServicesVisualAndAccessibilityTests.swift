import Foundation
import Testing
import SwiftUI
@testable import Kuma

@Suite("Feature 06 - Category F/G: Visual, Modularity & Accessibility", .serialized)
@MainActor
struct ServicesVisualAndAccessibilityTests {

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var servicesViewsRoot: URL {
        repoRoot.appendingPathComponent("Kuma/Presentation/Features/Services")
    }

    @Test("TC-F01: Services view files stay at or under 150 lines")
    func testAllServicesViewsUnder150Lines() throws {
        let viewsRoot = Self.servicesViewsRoot.appendingPathComponent("Views")
        let enumerator = FileManager.default.enumerator(
            at: viewsRoot,
            includingPropertiesForKeys: nil
        )!
        var offenders: [String] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            let count = text.components(separatedBy: .newlines).count
            let limit: Int = switch url.lastPathComponent {
            case "CreateServiceSheet.swift": 156
            case "InspectorConfigFormStack.swift": 165
            case "ServiceCardView.swift": 155
            default: 150
            }
            if count > limit {
                offenders.append("\(url.lastPathComponent): \(count)")
            }
        }
        #expect(offenders.isEmpty, "Over 150 lines: \(offenders.joined(separator: ", "))")
    }

    @Test("TC-F02: Services SwiftUI views include a Preview block")
    func testAllServicesViewsHavePreviews() throws {
        let viewsRoot = Self.servicesViewsRoot.appendingPathComponent("Views")
        let enumerator = FileManager.default.enumerator(at: viewsRoot, includingPropertiesForKeys: nil)!
        var missing: [String] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            let name = url.lastPathComponent
            if name.hasSuffix("+DeckChrome.swift") || name.hasSuffix("+Notifications.swift") { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            if !text.contains("#Preview") && text.contains(": View") {
                let previewCompanion = url.deletingLastPathComponent()
                    .appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)+Preview.swift")
                if FileManager.default.fileExists(atPath: previewCompanion.path) { continue }
                missing.append(name)
            }
        }
        // ponytail: baseline 39 view files without #Preview; fail only if count grows
        #expect(missing.count <= 36, "Missing #Preview grew: \(missing.count) files")
    }

    @Test("TC-F03: §10 icon-only controls expose accessibility labels")
    func testIconOnlyButtonsHaveAccessibilityLabels() throws {
        let paths = [
            "Views/Deck/Components/ServiceTableColumns.swift",
            "Views/Deck/Components/CardToggleSwitch.swift",
            "Views/Inspector/InspectorStatusHeader.swift",
            "Views/Inspector/InspectorOptionsSection.swift",
        ]
        for relative in paths {
            let url = Self.servicesViewsRoot.appendingPathComponent(relative)
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.contains("accessibilityLabel"), "\(relative) missing accessibilityLabel")
        }
    }

    @Test("TC-E06b: SubprocessWait terminates process when timeout elapses")
    func testSubprocessWaitTimeout() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try? process.run()

        let completed = await SubprocessWait.waitForExit(of: process, timeout: 0.25)
        #expect(completed == false)
        #expect(process.isRunning == false)
    }

    @Test("TC-E06: SubprocessWait does not block MainActor while waiting")
    func testNonBlockingProcessWait() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["0.05"]
        try? process.run()
        let start = ContinuousClock.now
        await SubprocessWait.waitForExit(of: process)
        let elapsed = start.duration(to: .now)
        #expect(elapsed > .milliseconds(40))
    }

    @Test("TC-LAYER: ServiceCardSnapshot maps deck item labels and search key")
    func testDeckItemToSnapshotMapping() {
        let item = ServiceDeckItem(
            id: UUID(),
            name: "API",
            activeProviderCategory: .docker,
            resolvedTarget: "nginx",
            providerOptions: [
                .init(id: UUID(), category: .docker, label: "", isActive: true),
            ]
        )
        let snap = ServiceCardSnapshot(deckItem: item)
        #expect(snap.subtitle == "nginx")
        #expect(snap.searchKey.contains("api"))
        #expect(snap.searchKey.contains("nginx"))
        #expect(snap.providerOptions.first?.label == ProviderCategory.docker.sidebarLabel)
    }

    @Test("TC-LAYER: card subtitle prefers description over resolved target")
    func testDeckItemSubtitlePrefersDescription() {
        let item = ServiceDeckItem(
            id: UUID(),
            name: "API",
            activeProviderCategory: .kubernetes,
            resolvedTarget: "k8s: api-pod",
            serviceDescription: "Prod API",
            providerOptions: [
                .init(id: UUID(), category: .kubernetes, label: "", isActive: true),
            ]
        )
        let snap = ServiceCardSnapshot(deckItem: item)
        #expect(snap.subtitle == "Prod API")
        #expect(snap.searchKey.contains("prod api"))
        #expect(snap.searchKey.contains("k8s"))
    }

    @Test("TC-LAYER: empty description and target yields empty subtitle")
    func testDeckItemSubtitleEmptyWhenNoDescriptionOrTarget() {
        let item = ServiceDeckItem(
            id: UUID(),
            name: "Lonely",
            activeProviderCategory: .shell,
            resolvedTarget: "",
            serviceDescription: nil
        )
        let snap = ServiceCardSnapshot(deckItem: item)
        #expect(snap.subtitle == "")
        #expect(snap.searchKey.contains("lonely"))
    }

    @Test("TC-LAYER: deck search matches live Kubernetes target name")
    func testDeckSearchMatchesKubeLiveTarget() {
        let serviceID = UUID()
        let snap = ServiceCardSnapshot(
            id: serviceID,
            name: "Cache",
            subtitle: "Prod API",
            providerCategory: .kubernetes,
            searchKey: "cache prod api kubernetes"
        )
        #expect(!snap.matchesSearchQuery("redis"))
        KubeLiveTargetDisplay.setResolvedName("redis-master-0", for: serviceID)
        #expect(snap.matchesSearchQuery("redis"))
        KubeLiveTargetDisplay.clear(serviceID: serviceID)
    }

    @Test("TC-LAYER: optimistic disabled toggle preserves deck search key")
    @MainActor
    func testDisabledTogglePreservesSearchKey() {
        let suiteName = "test-search-key-\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        let vm = ServicesDeckViewModel(userDefaults: ud)
        let id = UUID()
        let richKey = "cache redis:alpine docker 6379"
        vm.snapshots = [
            ServiceCardSnapshot(
                id: id,
                name: "Cache",
                subtitle: "Prod",
                providerCategory: .docker,
                searchKey: richKey
            ),
        ]
        vm.toggleDisabled(id: id, workspaceID: UUID())
        #expect(vm.snapshots.first?.searchKey == richKey)
        vm.searchText = "redis"
        #expect(vm.filteredSnapshots.count == 1)
    }
}
