import Foundation
import Observation
import SwiftUI
import os

@Observable
@MainActor
public final class ServiceInspectorViewModel {
    static let logger = Logger(subsystem: "lokastudio.kuma", category: "ServiceInspectorViewModel")

    public var serviceID: UUID
    public let workspaceID: UUID
    let serviceRepository: any ServiceRepositoryProtocol

    public var service: Service? = nil
    public var isLoadingServiceDetail: Bool = false
    public var providers: [Provider] = []
    public var activeProviderID: UUID? = nil
    public var draftPorts: [KumaPortMappingItem] = []

    public var isViewingLogs: Bool = false
    public var configurationIssues: [ConfigurationIssue] = []
    public var showDeleteConfirmation: Bool = false
    public var stateStore: ServiceStateStore?
    public var kubeConfigVM: KubeConfigViewModel? = nil

    var autoSaveTask: Task<Void, Never>? = nil
    var kubeAsyncValidationMessage: String?
    var pendingSaveRevision: UInt = 0
    var lastCommittedRevision: UInt = 0
    /// True after the user edits port rows; avoids wiping DB ports on unrelated auto-saves.
    var portsDraftDirty: Bool = false

    public var sshAuthType: SSHAuthType = .key

    public var executionState: ServiceExecutionState {
        stateStore?.state(for: serviceID) ?? (isRunning ? .running(pid: 0) : .idle)
    }

    public var isRunning: Bool {
        stateStore?.state(for: serviceID).isOperational ?? _legacyIsRunning
    }
    private var _legacyIsRunning: Bool = false

    public var activeProvider: Provider? {
        if let activeProviderID {
            return providers.first(where: { $0.id == activeProviderID })
        }
        return providers.first
    }

    public var activeCategory: ProviderCategory {
        activeProvider?.type ?? .docker
    }

    public func clearAfterExternalDeletion() {
        service = nil
        providers = []
        activeProviderID = nil
        draftPorts = []
        portsDraftDirty = false
        cancelAutoSave()
    }

    func postUpdatedNotification() {
        KumaServiceNotification.postServiceUpdated(
            serviceID: serviceID,
            source: KumaServiceNotification.sourceInspector
        )
    }

    public init(
        serviceID: UUID,
        workspaceID: UUID,
        serviceRepository: any ServiceRepositoryProtocol = ServiceRepository(),
        stateStore: ServiceStateStore? = nil
    ) {
        self.serviceID = serviceID
        self.workspaceID = workspaceID
        self.serviceRepository = serviceRepository
        self.stateStore = stateStore
    }
}
