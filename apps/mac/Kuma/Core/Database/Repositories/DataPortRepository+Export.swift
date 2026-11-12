import Foundation
import GRDB
import os

extension DataPortRepository {
    func exportSingleServiceBackup(serviceID: UUID) async throws -> DataPortService.KumaBackup {
        let (service, providers, ports) = try await dbWriter.read { db -> (Service?, [Provider], [ServicePortMapping]) in
            let svc = try Service.fetchOne(db, key: serviceID.uuidString)
            let provs = try Provider.filter(Column("serviceID") == serviceID.uuidString).fetchAll(db)
            let portMaps = try ServicePortMapping.filter(Column("serviceID") == serviceID.uuidString).fetchAll(db)
            return (svc, provs, portMaps)
        }

        guard let svc = service else {
            throw NSError(domain: "lokastudio.kuma.dataport", code: 404, userInfo: [NSLocalizedDescriptionKey: "Service \(serviceID) not found."])
        }

        let exportService = DataPortService.ExportService(
            id: svc.id,
            name: svc.name,
            icon: svc.icon,
            colorHex: svc.colorHex,
            description: svc.description,
            activeProviderID: svc.activeProviderID,
            workspaceID: svc.workspaceID,
            groupIDs: Array(svc.groupIDs),
            isDisabled: svc.isDisabled,
            isStarred: svc.isStarred
        )

        let exportProviders = try providers.map { try Self.toExportProvider($0) }
        let exportPorts = ports.map { p in
            DataPortService.ExportPortMapping(
                id: p.id,
                providerID: p.providerID ?? svc.activeProviderID ?? svc.id,
                localPort: p.localPort,
                remotePort: p.remotePort
            )
        }
        let kubeConfigs = try await kubeConfigsForExport(exportProviders: exportProviders)

        return DataPortService.KumaBackup(
            version: DataPortService.currentVersion,
            exportedAt: Date(),
            workspaces: [],
            workspaceImages: nil,
            groups: nil,
            services: [exportService],
            providers: exportProviders,
            portMappings: exportPorts,
            kubeConfigs: kubeConfigs
        )
    }

    /// Exports full relational data from SQLite into KumaBackup payload.
    /// Image I/O is done outside the DB read closure to keep transaction short.
    public func exportAll() async throws -> DataPortService.KumaBackup {
        // 1. Read relational data inside a single DB read transaction
        let (workspaces, exportGroups, exportServices, exportProviders, exportPortMappings) = try await dbWriter.read { db in
            let workspaces = try Workspace.order(Column("sortOrder").asc, Column("createdAt").asc).fetchAll(db)
            let groups = try ServiceGroup.order(Column("sortOrder").asc, Column("createdAt").asc).fetchAll(db)
            let services = try Service.order(Column("createdAt").asc).fetchAll(db)
            let providers = try Provider.order(Column("createdAt").asc).fetchAll(db)
            let portMappings = try ServicePortMapping.fetchAll(db)
            let memberships = try ServiceGroupMembershipRecord.fetchAll(db)

            var groupsByServiceID: [UUID: [UUID]] = [:]
            for m in memberships {
                groupsByServiceID[m.serviceID, default: []].append(m.groupID)
            }

            let exportServices = services.map { s in
                DataPortService.ExportService(
                    id: s.id,
                    name: s.name,
                    icon: s.icon,
                    colorHex: s.colorHex,
                    description: s.description,
                    activeProviderID: s.activeProviderID,
                    workspaceID: s.workspaceID,
                    groupIDs: groupsByServiceID[s.id],
                    isDisabled: s.isDisabled,
                    isStarred: s.isStarred
                )
            }

            let exportProviders = try providers.map { p in
                try Self.toExportProvider(p)
            }

            let exportPortMappings = portMappings.map { pm in
                var associatedProviderID = pm.serviceID ?? pm.id
                if let sID = pm.serviceID {
                    if let service = services.first(where: { $0.id == sID }),
                       let activePID = service.activeProviderID {
                        associatedProviderID = activePID
                    } else if let firstProv = providers.first(where: { $0.serviceID == sID }) {
                        associatedProviderID = firstProv.id
                    }
                }

                return DataPortService.ExportPortMapping(
                    id: pm.id,
                    providerID: pm.providerID ?? associatedProviderID,
                    localPort: pm.localPort,
                    remotePort: pm.remotePort
                )
            }

            return (workspaces, groups, exportServices, exportProviders, exportPortMappings)
        }

        // 2. Load Base64 images outside DB closure (pure disk I/O, no transaction held)
        var imagesMap: [String: String] = [:]
        for ws in workspaces {
            if let imagePath = ws.imagePath,
               let base64 = WorkspaceImageStore.shared.loadBase64Image(for: imagePath) {
                imagesMap[ws.id.uuidString] = base64
            }
        }

        let kubeConfigs = try await kubeConfigsForExport(exportProviders: exportProviders)

        return DataPortService.KumaBackup(
            version: DataPortService.currentVersion,
            exportedAt: Date(),
            workspaces: workspaces,
            workspaceImages: imagesMap.isEmpty ? nil : imagesMap,
            groups: exportGroups,
            services: exportServices,
            providers: exportProviders,
            portMappings: exportPortMappings,
            kubeConfigs: kubeConfigs
        )
    }

    /// Restores full relational data into SQLite (Workspaces, Groups, Services, Providers, PortMappings).
    /// Image I/O is resolved before the DB write transaction to avoid holding the write lock during disk ops.
    public func exportWorkspace(id: UUID) async throws -> DataPortService.KumaBackup {
        let (workspaces, groups, exportServices, exportProviders, exportPortMappings) = try await dbWriter.read { db in
            let workspaces = try Workspace.filter(Column("id") == id.uuidString).fetchAll(db)
            let groups = try ServiceGroup.filter(Column("workspaceID") == id.uuidString).order(Column("sortOrder").asc).fetchAll(db)
            let services = try Service.filter(Column("workspaceID") == id.uuidString).order(Column("createdAt").asc).fetchAll(db)
            let serviceIDStrings = services.map { $0.id.uuidString }

            let providers: [Provider]
            let portMappings: [ServicePortMapping]
            let memberships: [ServiceGroupMembershipRecord]

            if !serviceIDStrings.isEmpty {
                providers = try Provider
                    .filter(serviceIDStrings.contains(Column("serviceID")))
                    .order(Column("createdAt").asc)
                    .fetchAll(db)
                portMappings = try ServicePortMapping
                    .filter(serviceIDStrings.contains(Column("serviceID")))
                    .fetchAll(db)
                memberships = try ServiceGroupMembershipRecord
                    .filter(serviceIDStrings.contains(Column("serviceID")))
                    .fetchAll(db)
            } else {
                providers = []
                portMappings = []
                memberships = []
            }

            var groupsByServiceID: [UUID: [UUID]] = [:]
            for m in memberships {
                groupsByServiceID[m.serviceID, default: []].append(m.groupID)
            }

            let exportServices = services.map { s in
                DataPortService.ExportService(
                    id: s.id,
                    name: s.name,
                    icon: s.icon,
                    colorHex: s.colorHex,
                    description: s.description,
                    activeProviderID: s.activeProviderID,
                    workspaceID: s.workspaceID,
                    groupIDs: groupsByServiceID[s.id],
                    isDisabled: s.isDisabled,
                    isStarred: s.isStarred
                )
            }

            let exportProviders = try providers.map { p in
                try Self.toExportProvider(p)
            }

            let exportPortMappings = portMappings.map { pm in
                var associatedProviderID = pm.serviceID ?? pm.id
                if let sID = pm.serviceID {
                    if let service = services.first(where: { $0.id == sID }),
                       let activePID = service.activeProviderID {
                        associatedProviderID = activePID
                    } else if let firstProv = providers.first(where: { $0.serviceID == sID }) {
                        associatedProviderID = firstProv.id
                    }
                }

                return DataPortService.ExportPortMapping(
                    id: pm.id,
                    providerID: pm.providerID ?? associatedProviderID,
                    localPort: pm.localPort,
                    remotePort: pm.remotePort
                )
            }

            return (workspaces, groups, exportServices, exportProviders, exportPortMappings)
        }

        var imagesMap: [String: String] = [:]
        for ws in workspaces {
            if let imagePath = ws.imagePath,
               let base64 = WorkspaceImageStore.shared.loadBase64Image(for: imagePath) {
                imagesMap[ws.id.uuidString] = base64
            }
        }

        let kubeConfigs = try await kubeConfigsForExport(exportProviders: exportProviders)

        return DataPortService.KumaBackup(
            version: DataPortService.currentVersion,
            exportedAt: Date(),
            workspaces: workspaces,
            workspaceImages: imagesMap.isEmpty ? nil : imagesMap,
            groups: groups,
            services: exportServices,
            providers: exportProviders,
            portMappings: exportPortMappings,
            kubeConfigs: kubeConfigs
        )
    }

    /// Selectively imports services directly into a target workspace (generating new UUIDs to prevent ID collision/stealing).
    /// Supports custom resolved names (e.g. for avoiding duplicate name collisions).

    private func kubeConfigsForExport(exportProviders: [DataPortService.ExportProvider]) async throws -> [DataPortService.ExportKubeConfig] {
        let ids = Self.collectReferencedKubeConfigIDs(from: exportProviders)
        return try await exportKubeConfigs(ids: ids)
    }

    private func exportKubeConfigs(ids: Set<UUID>) async throws -> [DataPortService.ExportKubeConfig] {
        guard !ids.isEmpty else { return [] }
        return try await dbWriter.read { db in
            var exported: [DataPortService.ExportKubeConfig] = []
            for id in ids {
                guard let row = try KubeConfig.fetchOne(db, key: id.uuidString) else { continue }
                exported.append(
                    DataPortService.ExportKubeConfig(
                        id: row.id,
                        name: row.name,
                        path: row.sourceFilePath,
                        encryptedConfigContent: row.configContent,
                        createdAt: row.createdAt,
                        updatedAt: row.updatedAt
                    )
                )
            }
            return exported
        }
    }

    public func exportSingleServiceJSON(serviceID: UUID) async throws -> String {
        let (service, providers, ports) = try await dbWriter.read { db -> (Service?, [Provider], [ServicePortMapping]) in
            let svc = try Service.fetchOne(db, key: serviceID.uuidString)
            let provs = try Provider.filter(Column("serviceID") == serviceID.uuidString).fetchAll(db)
            let portMaps = try ServicePortMapping.filter(Column("serviceID") == serviceID.uuidString).fetchAll(db)
            return (svc, provs, portMaps)
        }

        guard let svc = service else {
            throw NSError(domain: "lokastudio.kuma.dataport", code: 404, userInfo: [NSLocalizedDescriptionKey: "Service \(serviceID) not found."])
        }

        let exportService = DataPortService.ExportService(
            id: svc.id,
            name: svc.name,
            icon: svc.icon,
            colorHex: svc.colorHex,
            description: svc.description,
            activeProviderID: svc.activeProviderID,
            workspaceID: svc.workspaceID,
            groupIDs: Array(svc.groupIDs),
            isDisabled: svc.isDisabled,
            isStarred: svc.isStarred
        )

        let exportProviders = try providers.map { try Self.toExportProvider($0) }
        let exportPorts = ports.map { p in
            DataPortService.ExportPortMapping(
                id: p.id,
                providerID: p.providerID ?? svc.activeProviderID ?? svc.id,
                localPort: p.localPort,
                remotePort: p.remotePort
            )
        }
        let kubeConfigs = try await kubeConfigsForExport(exportProviders: exportProviders)

        let singleExport = DataPortService.SingleServiceExport(
            version: DataPortService.currentVersion,
            exportedAt: Date(),
            service: exportService,
            providers: exportProviders,
            portMappings: exportPorts,
            kubeConfigs: kubeConfigs
        )

        let data = try DataPortService.encodeSingleService(singleExport)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "lokastudio.kuma.dataport", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to encode service JSON."])
        }
        return jsonString
    }
}
