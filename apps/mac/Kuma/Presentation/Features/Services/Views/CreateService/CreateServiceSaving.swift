import Foundation
import os

enum CreateServiceSaving {
    private static let logger = Logger(subsystem: "lokastudio.kuma", category: "CreateServiceSheet")

    @MainActor
    static func beginCreate(
        workspaceID: UUID,
        inputs: CreateServicePayloadBuilder.DraftInputs,
        creationDefaults: CreateServiceCreationDefaults,
        serviceRepository: any ServiceRepositoryProtocol,
        onServiceCreated: (() -> Void)?,
        dismiss: @escaping () -> Void,
        onSavingFailed: @escaping () -> Void
    ) {
        save(
            workspaceID: workspaceID,
            inputs: inputs,
            creationDefaults: creationDefaults,
            serviceRepository: serviceRepository,
            onSuccess: {
                onServiceCreated?()
                dismiss()
            },
            onFailure: onSavingFailed
        )
    }

    @MainActor
    static func save(
        workspaceID: UUID,
        inputs: CreateServicePayloadBuilder.DraftInputs,
        creationDefaults: CreateServiceCreationDefaults = CreateServiceCreationDefaults(),
        serviceRepository: any ServiceRepositoryProtocol,
        onSuccess: @escaping () -> Void,
        onFailure: @escaping () -> Void
    ) {
        Task {
            do {
                var (service, provider, portMappings) = try CreateServicePayloadBuilder.buildPayload(
                    workspaceID: workspaceID,
                    inputs: inputs
                )
                if creationDefaults.starOnCreate {
                    service.isStarred = true
                }
                if let groupID = creationDefaults.initialGroupID {
                    service.groupIDs = [groupID]
                }
                try await serviceRepository.insertService(service, defaultProvider: provider, portMappings: portMappings)
                onSuccess()
            } catch {
                logger.error("Failed to create service: \(error.localizedDescription)")
                onFailure()
            }
        }
    }
}
