import Foundation
import Testing
@testable import Kuma

@Suite("Feature 06 - Category A: Services Initial State & Domain Baseline", .serialized)
@MainActor
struct ServicesInitialStateTests {

    // MARK: - [TC-A01] Service Entity Default Properties
    @Test("TC-A01: Service model initializes with expected defaults")
    func testServiceEntityDefaultProperties() {
        let id = UUID()
        let service = Service(id: id, name: "Redis Cache")

        #expect(service.id == id)
        #expect(service.name == "Redis Cache")
        #expect(service.icon == nil)
        #expect(service.colorHex == nil)
        #expect(service.description == nil)
        #expect(service.activeProviderID == nil)
        #expect(service.workspaceID == nil)
        #expect(service.groupIDs.isEmpty)
        #expect(!service.isDisabled)
        #expect(!service.isStarred)
    }

    // MARK: - [TC-A02] Provider Entity Resolved Target
    @Test("TC-A02: Provider entity computes resolvedTarget correctly for various types")
    func testProviderEntityResolvedTarget() {
        let serviceID = UUID()

        // Shell Provider
        let shellProv = Provider(
            serviceID: serviceID,
            type: .shell,
            runCommand: "npm run dev"
        )
        #expect(shellProv.resolvedTarget == "npm run dev")

        // SSH Provider
        let sshProv = Provider(
            serviceID: serviceID,
            type: .ssh,
            sshHost: "192.168.1.50",
            sshUser: "deploy",
            sshPort: 2222
        )
        #expect(sshProv.resolvedTarget == "SSH: deploy@192.168.1.50:2222")

        // HTTP Check Provider
        let httpProv = Provider(
            serviceID: serviceID,
            type: .httpCheck,
            httpCheckUrl: "https://api.example.com/healthz"
        )
        #expect(httpProv.resolvedTarget == "HTTP: https://api.example.com/healthz")

        // Tunnel Provider
        let tunnelProv = Provider(
            serviceID: serviceID,
            type: .tunnel,
            tunnelType: "ngrok",
            tunnelTargetUrl: "localhost:3000"
        )
        #expect(tunnelProv.resolvedTarget == "Ngrok Tunnel -> localhost:3000")

        // Process Monitor
        let monitorProv = Provider(
            serviceID: serviceID,
            type: .processMonitor,
            monitorProcessName: "postgres"
        )
        #expect(monitorProv.resolvedTarget == "Monitor: postgres")
    }

    // MARK: - [TC-A03] Service Execution State Discrete Transitions
    @Test("TC-A03: ServiceExecutionState discrete transitions and properties")
    func testServiceExecutionStateDiscreteTransitions() {
        let idle = ServiceExecutionState.idle
        #expect(!idle.isOperational)
        #expect(!idle.isLoading)
        #expect(idle.processIdentifier == nil)
        #expect(idle.title == "Stopped")
        #expect(idle.legacyState == .stopped)

        let starting = ServiceExecutionState.starting
        #expect(starting.isOperational)
        #expect(starting.isLoading)
        #expect(starting.processIdentifier == nil)
        #expect(starting.title == "Starting")
        #expect(starting.legacyState == .starting)

        let running = ServiceExecutionState.running(pid: 12345)
        #expect(running.isOperational)
        #expect(!running.isLoading)
        #expect(running.processIdentifier == 12345)
        #expect(running.title == "Running")
        #expect(running.legacyState == .running)

        let stopping = ServiceExecutionState.stopping
        #expect(!stopping.isOperational)
        #expect(stopping.isLoading)
        #expect(stopping.legacyState == .stopping)

        let reconnecting = ServiceExecutionState.reconnecting(attempt: 2, maxAttempts: 3)
        #expect(reconnecting.isOperational)
        #expect(reconnecting.isLoading)
        #expect(reconnecting.title == "Reconnecting (2/3)")
        #expect(reconnecting.legacyState == .reconnecting)

        let crashed = ServiceExecutionState.crashed(exitCode: 137)
        #expect(!crashed.isOperational)
        #expect(!crashed.isLoading)
        #expect(crashed.title == "Crashed")
        #expect(crashed.legacyState == .crashed)

        let failed = ServiceExecutionState.failed(reason: "Binary not found")
        #expect(!failed.isOperational)
        #expect(!failed.isLoading)
        #expect(failed.title == "Failed")
        #expect(failed.legacyState == .crashed)
    }

    // MARK: - [TC-A04] ServiceCardSnapshot Projection Integrity
    @Test("TC-A04: ServiceCardSnapshot maintains projection integrity without leaking raw credentials")
    func testServiceCardSnapshotProjectionIntegrity() {
        let serviceID = UUID()
        let provID = UUID()
        let opt = ServiceCardSnapshot.ProviderOption(
            id: provID,
            category: .ssh,
            label: "Production SSH",
            isActive: true
        )

        let snapshot = ServiceCardSnapshot(
            id: serviceID,
            name: "Backend Gateway",
            groupIDs: [],
            isDisabled: false,
            isStarred: true,
            subtitle: "SSH: root@gateway.internal:22",
            providerCategory: .ssh,
            portDisplays: [8080, 8443],
            providerOptions: [opt]
        )

        #expect(snapshot.id == serviceID)
        #expect(snapshot.name == "Backend Gateway")
        #expect(snapshot.isStarred)
        #expect(snapshot.portDisplays == [8080, 8443])
        #expect(snapshot.searchKey == "backend gateway ssh: root@gateway.internal:22")
        #expect(snapshot.providerOptions.count == 1)

        let toggled = snapshot.toggling(starred: false)
        #expect(!toggled.isStarred)
        #expect(toggled.searchKey == snapshot.searchKey)
    }

    // MARK: - [TC-A05] ProviderCategory Domain Purity
    @Test("TC-A05: ProviderCategory is pure domain enum with deterministic stable IDs")
    func testProviderCategoryDomainPurity() {
        for cat in ProviderCategory.allCases {
            #expect(!cat.sidebarLabel.isEmpty)
            #expect(!cat.addTooltip.isEmpty)
            #expect(cat.stableID == UUID.stable("provider.\(cat.rawValue)"))
        }
    }

    // MARK: - [TC-A06] ServicePortMapping Validation
    @Test("TC-A06: ServicePortMapping displays port mapping string consistently")
    func testServicePortMappingValidation() {
        let mapping = ServicePortMapping(
            localPort: 8080,
            remotePort: 80
        )
        #expect(mapping.localPort == 8080)
        #expect(mapping.remotePort == 80)
        #expect(mapping.protocolType == "TCP")
        #expect(mapping.displayString == "8080:80")
    }

    @Test("TC-A06b: Port UI strings stay plain decimal without grouping")
    func testKumaPortFormattingPlainDecimal() {
        #expect(KumaPortFormatting.plain(8080) == "8080")
        #expect(KumaPortFormatting.plain(9200) == "9200")
        #expect(!KumaPortFormatting.plain(9200).contains("."))
    }
}
