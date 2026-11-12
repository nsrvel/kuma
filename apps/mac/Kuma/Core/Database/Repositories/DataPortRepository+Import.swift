import Foundation
import GRDB
import os

extension DataPortRepository {
    public func importAll(from backup: DataPortService.KumaBackup) async throws {
        // 1. Resolve & save any Base64 images to disk BEFORE opening DB write transaction
        var resolvedImagePaths: [UUID: String] = [:]
        if let imagesMap = backup.workspaceImages {
            for ws in backup.workspaces {
                if let base64 = imagesMap[ws.id.uuidString],
                   let fileName = WorkspaceImageStore.shared.saveBase64Image(base64, workspaceID: ws.id) {
                    resolvedImagePaths[ws.id] = fileName
                }
            }
        }

        // 2. Write all relational data in a single atomic DB transaction
        let paths = resolvedImagePaths
        try await dbWriter.write { db in
            try Self.importKubeConfigs(backup.kubeConfigs, db: db)

            // Restore Workspaces
            for ws in backup.workspaces {
                var workspaceToSave = ws
                if let resolvedPath = paths[ws.id] {
                    workspaceToSave.imagePath = resolvedPath
                }
                try workspaceToSave.save(db)
            }

            // Restore Groups if present
            if let groups = backup.groups {
                for group in groups {
                    try group.save(db)
                }
            }

            // Map & Restore Services
            for exportService in backup.services {
                let service = Service(
                    id: exportService.id,
                    name: exportService.name,
                    icon: exportService.icon,
                    colorHex: exportService.colorHex,
                    description: exportService.description,
                    activeProviderID: exportService.activeProviderID,
                    workspaceID: exportService.workspaceID,
                    groupIDs: Set(exportService.groupIDs ?? []),
                    isDisabled: exportService.isDisabled ?? false,
                    isStarred: exportService.isStarred ?? false
                )
                try service.save(db)

                // Restore group memberships
                if let gIDs = exportService.groupIDs {
                    for gID in gIDs {
                        let membership = ServiceGroupMembershipRecord(serviceID: service.id, groupID: gID)
                        try membership.save(db)
                    }
                }
            }

            // Map & Restore Providers — 100% full fields preservation
            for exportProvider in backup.providers {
                let provider = Self.fromExportProvider(exportProvider)
                try provider.save(db)
            }

            // Map & Restore Port Mappings (O(1) In-Memory Lookup, Zero N+1 DB roundtrips)
            let providerToServiceMap = Dictionary(uniqueKeysWithValues: backup.providers.map { ($0.id, $0.serviceID) })
            let serviceIdSet = Set(backup.services.map(\.id))

            for exportPort in backup.portMappings {
                var targetServiceID: UUID? = nil
                if let mappedSID = providerToServiceMap[exportPort.providerID] {
                    targetServiceID = mappedSID
                } else if serviceIdSet.contains(exportPort.providerID) {
                    targetServiceID = exportPort.providerID
                }

                if let targetServiceID {
                    try db.execute(
                        sql: """
                        INSERT INTO portMapping (id, serviceID, localPort, remotePort, protocolType, providerID)
                        VALUES (?, ?, ?, ?, ?, ?)
                        ON CONFLICT(id) DO UPDATE SET
                            localPort=excluded.localPort,
                            remotePort=excluded.remotePort,
                            providerID=excluded.providerID
                        """,
                        arguments: [
                            exportPort.id.uuidString,
                            targetServiceID.uuidString,
                            exportPort.localPort,
                            exportPort.remotePort,
                            "TCP",
                            exportPort.providerID.uuidString
                        ]
                    )
                }
            }

            self.logger.info("Imported backup: \(backup.workspaces.count) workspaces, \(backup.services.count) services, \(backup.providers.count) providers")
        }
    }

    /// Selectively restores chosen workspaces and services into SQLite.
    public func importSelective(
        from backup: DataPortService.KumaBackup,
        selectedWorkspaceIDs: Set<UUID>,
        selectedServiceIDs: Set<UUID>
    ) async throws {
        let filteredWorkspaces = backup.workspaces.filter { selectedWorkspaceIDs.contains($0.id) }
        let filteredServices = backup.services.filter { selectedServiceIDs.contains($0.id) }
        let filteredServiceIdSet = Set(filteredServices.map(\.id))
        let filteredProviders = backup.providers.filter { filteredServiceIdSet.contains($0.serviceID) }
        let filteredProviderIdSet = Set(filteredProviders.map(\.id))
        let filteredPortMappings = backup.portMappings.filter {
            filteredProviderIdSet.contains($0.providerID) || filteredServiceIdSet.contains($0.providerID)
        }
        let referencedKubeIDs = Self.collectReferencedKubeConfigIDs(from: filteredProviders)
        let filteredKubeConfigs = backup.kubeConfigs.filter { referencedKubeIDs.contains($0.id) }

        let filteredBackup = DataPortService.KumaBackup(
            version: backup.version,
            exportedAt: backup.exportedAt,
            workspaces: filteredWorkspaces,
            workspaceImages: backup.workspaceImages,
            groups: backup.groups?.filter { g in
                if let wsID = g.workspaceID { return selectedWorkspaceIDs.contains(wsID) }
                return true
            },
            services: filteredServices,
            providers: filteredProviders,
            portMappings: filteredPortMappings,
            kubeConfigs: filteredKubeConfigs
        )

        try await importAll(from: filteredBackup)
    }

    /// Exports only data belonging to a single workspace.
    public func importIntoWorkspace(
        targetWorkspaceID: UUID,
        backup: DataPortService.KumaBackup,
        selectedServiceIDs: Set<UUID>,
        resolvedNames: [UUID: String] = [:]
    ) async throws {
        var serviceIDMap: [UUID: UUID] = [:]
        var providerIDMap: [UUID: UUID] = [:]

        let chosenExportServices = backup.services.filter { selectedServiceIDs.contains($0.id) }
        for s in chosenExportServices {
            serviceIDMap[s.id] = UUID()
        }

        let newServices = chosenExportServices.map { s in
            let finalName = resolvedNames[s.id] ?? s.name
            let mappedActiveProvID = s.activeProviderID.flatMap { providerIDMap[$0] }
            return DataPortService.ExportService(
                id: serviceIDMap[s.id] ?? UUID(),
                name: finalName,
                icon: s.icon,
                colorHex: s.colorHex,
                description: s.description,
                activeProviderID: mappedActiveProvID,
                workspaceID: targetWorkspaceID,
                groupIDs: s.groupIDs,
                isDisabled: s.isDisabled,
                isStarred: s.isStarred
            )
        }

        // Map and re-ID Providers
        let oldServiceIdSet = Set(chosenExportServices.map(\.id))
        let chosenExportProviders = backup.providers.filter { oldServiceIdSet.contains($0.serviceID) }
        for p in chosenExportProviders {
            providerIDMap[p.id] = UUID()
        }

        let newProviders = chosenExportProviders.map { p in
            return DataPortService.ExportProvider(
                id: providerIDMap[p.id] ?? UUID(),
                serviceID: serviceIDMap[p.serviceID] ?? p.serviceID,
                type: p.type,
                label: p.label,
                runCommand: p.runCommand,
                yamlConfig: p.yamlConfig,
                composeFilePath: p.composeFilePath,
                kubeContext: p.kubeContext,
                kubeNamespace: p.kubeNamespace,
                targetName: p.targetName,
                kubeConfigID: p.kubeConfigID,
                customKubeConfigPath: p.customKubeConfigPath,
                kubeTargetType: p.kubeTargetType,
                usePattern: p.usePattern,
                initialScript: p.initialScript,
                initialScriptPath: p.initialScriptPath,
                workingDirectory: p.workingDirectory,
                sshHost: p.sshHost,
                sshUser: p.sshUser,
                sshPort: p.sshPort,
                sshKeyPath: p.sshKeyPath,
                sshPassword: p.sshPassword,
                httpCheckUrl: p.httpCheckUrl,
                httpCheckInterval: p.httpCheckInterval,
                tunnelType: p.tunnelType,
                tunnelTargetUrl: p.tunnelTargetUrl,
                ngrokAuthToken: p.ngrokAuthToken,
                monitorProcessName: p.monitorProcessName,
                monitorInterval: p.monitorInterval,
                autoReconnect: p.autoReconnect
            )
        }

        // Map and re-ID Port Mappings
        let oldProviderIdSet = Set(chosenExportProviders.map(\.id))
        let chosenExportPortMappings = backup.portMappings.filter {
            oldProviderIdSet.contains($0.providerID) || oldServiceIdSet.contains($0.providerID)
        }

        let newPortMappings = chosenExportPortMappings.map { pm in
            let newProvID: UUID
            if let mappedPID = providerIDMap[pm.providerID] {
                newProvID = mappedPID
            } else if let mappedSID = serviceIDMap[pm.providerID] {
                newProvID = mappedSID
            } else {
                newProvID = pm.providerID
            }

            return DataPortService.ExportPortMapping(
                id: UUID(),
                providerID: newProvID,
                localPort: pm.localPort,
                remotePort: pm.remotePort
            )
        }

        let referencedKubeIDs = Self.collectReferencedKubeConfigIDs(from: newProviders)
        let kubeConfigs = backup.kubeConfigs.filter { referencedKubeIDs.contains($0.id) }

        let newBackup = DataPortService.KumaBackup(
            version: backup.version,
            exportedAt: backup.exportedAt,
            workspaces: [],
            workspaceImages: nil,
            groups: backup.groups,
            services: newServices,
            providers: newProviders,
            portMappings: newPortMappings,
            kubeConfigs: kubeConfigs
        )

        try await importAll(from: newBackup)
    }

}
