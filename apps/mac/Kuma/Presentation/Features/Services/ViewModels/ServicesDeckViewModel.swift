import SwiftUI
import Observation
import os

@MainActor
@Observable
public final class ServicesDeckViewModel {
    static let logger = Logger(subsystem: "lokastudio.kuma", category: "ServicesDeckViewModel")

    // MARK: - Filter Inputs (each triggers recompute on change)

    public var searchText: String = "" {
        didSet {
            if oldValue != searchText {
                recomputeFilteredSnapshots()
            }
        }
    }
    public var selectedStatuses: Set<ServiceStatusFilterOption> = [] {
        didSet { if oldValue != selectedStatuses { recomputeFilteredSnapshots() } }
    }
    public var selectedProviders: Set<ProviderCategory> = [] {
        didSet { if oldValue != selectedProviders { recomputeFilteredSnapshots() } }
    }
    public var sortBy: ServiceSortOption = .name {
        didSet { if oldValue != sortBy { recomputeFilteredSnapshots() } }
    }
    public var isStarredOnly: Bool = false {
        didSet { if oldValue != isStarredOnly { recomputeFilteredSnapshots() } }
    }
    public var filterGroupID: UUID? = nil {
        didSet { if oldValue != filterGroupID { recomputeFilteredSnapshots() } }
    }

    // MARK: - Non-Filter State (changes do NOT trigger recompute)

    public var viewMode: DeckViewMode = .card
    public var isInspectorPresented: Bool = false
    public var selectedServiceID: UUID? = nil
    public var hasInitialLoaded: Bool = false
    public var servicePendingDeletion: ServiceCardSnapshot? = nil

    // MARK: - Tier 1: Static Snapshots (~64B per item)

    public var snapshots: [ServiceCardSnapshot] = [] {
        didSet { recomputeFilteredSnapshots() }
    }

    // MARK: - Tier 2: Cached Filtered Output (B1 Fix)

    public var filteredSnapshots: [ServiceCardSnapshot] = []
    public var filterVersion: Int = 0

    public var canStartAll: Bool {
        bulkActionSnapshots.contains { !$0.isDisabled && !isOperational($0.id) }
    }

    public var canStopAll: Bool {
        bulkActionSnapshots.contains { isOperational($0.id) }
    }

    public func runtime(for id: UUID) -> ServiceRuntimeState {
        stateStore?.runtime(for: id) ?? .idle
    }

    func isOperational(_ id: UUID) -> Bool {
        stateStore?.state(for: id).isOperational == true
    }

    public func notifyExecutionStatesChanged() {
        let hasSearch = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasSearch || !selectedStatuses.isEmpty || sortBy == .status {
            recomputeFilteredSnapshots()
        }
    }

    // MARK: - Groups Data
    public var groups: [ServiceGroup] = []

    let serviceRepository: any ServiceRepositoryProtocol
    let groupRepository: any ServiceGroupRepositoryProtocol
    public var stateStore: ServiceStateStore?
    let userDefaults: UserDefaults
    var loadTask: Task<Void, Never>? = nil

    public init(
        serviceRepository: any ServiceRepositoryProtocol = ServiceRepository(),
        groupRepository: any ServiceGroupRepositoryProtocol = ServiceGroupRepository(),
        stateStore: ServiceStateStore? = nil,
        userDefaults: UserDefaults = .standard,
        isStarredOnly: Bool = false,
        filterGroupID: UUID? = nil
    ) {
        self.serviceRepository = serviceRepository
        self.groupRepository = groupRepository
        self.stateStore = stateStore
        self.userDefaults = userDefaults
        self.isStarredOnly = isStarredOnly
        self.filterGroupID = filterGroupID
    }
}
