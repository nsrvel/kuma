import Foundation
import GRDB

extension ServiceRepository {
    public func fetchDeckItems(forWorkspace workspaceID: UUID) async throws -> [ServiceDeckItem] {
        try await dbWriter.read { db in
            let services = try Service
                .filter(Column("workspaceID") == workspaceID.uuidString)
                .order(Column("createdAt").asc)
                .fetchAll(db)

            guard !services.isEmpty else { return [] }

            let serviceIDStrings = services.map { $0.id.uuidString }

            let allProviders = try Provider
                .filter(serviceIDStrings.contains(Column("serviceID")))
                .order(Column("createdAt").asc)
                .fetchAll(db)

            var providersByServiceID: [UUID: [Provider]] = [:]
            var providerByID: [UUID: Provider] = [:]
            providersByServiceID.reserveCapacity(services.count)
            providerByID.reserveCapacity(allProviders.count)

            for provider in allProviders {
                providersByServiceID[provider.serviceID, default: []].append(provider)
                providerByID[provider.id] = provider
            }

            let allPortMappings = try ServicePortMapping
                .filter(serviceIDStrings.contains(Column("serviceID")))
                .fetchAll(db)

            var portsByServiceID: [UUID: [Int]] = [:]
            portsByServiceID.reserveCapacity(services.count)
            for service in services {
                let activeProvID = service.activeProviderID ?? providersByServiceID[service.id]?.first?.id
                portsByServiceID[service.id] = Self.localPortsForActiveProvider(
                    mappings: allPortMappings,
                    serviceID: service.id,
                    activeProviderID: activeProvID
                )
            }

            let allMemberships = try ServiceGroupMembershipRecord
                .filter(serviceIDStrings.contains(Column("serviceID")))
                .fetchAll(db)

            var groupsByServiceID: [UUID: Set<UUID>] = [:]
            groupsByServiceID.reserveCapacity(services.count)
            for membership in allMemberships {
                groupsByServiceID[membership.serviceID, default: []].insert(membership.groupID)
            }

            var items: [ServiceDeckItem] = []
            items.reserveCapacity(services.count)

            for service in services {
                var category: ProviderCategory = .docker
                var resolvedTarget = ""

                if let activeProvID = service.activeProviderID,
                   let provider = providerByID[activeProvID] {
                    category = provider.type
                    resolvedTarget = provider.resolvedTarget
                } else if let firstProv = providersByServiceID[service.id]?.first {
                    category = firstProv.type
                    resolvedTarget = firstProv.resolvedTarget
                }

                let groupIDs = groupsByServiceID[service.id] ?? []
                let provs = providersByServiceID[service.id] ?? []
                let activeID = service.activeProviderID ?? provs.first?.id
                let providerOptions = provs.map { p in
                    let rawLabel = p.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return ServiceDeckItem.DeckProviderOption(
                        id: p.id,
                        category: p.type,
                        label: rawLabel,
                        isActive: (p.id == activeID)
                    )
                }

                items.append(
                    ServiceDeckItem(
                        id: service.id,
                        name: service.name,
                        groupIDs: groupIDs,
                        isDisabled: service.isDisabled,
                        isStarred: service.isStarred,
                        activeProviderCategory: category,
                        resolvedTarget: resolvedTarget,
                        serviceDescription: service.description,
                        localPorts: portsByServiceID[service.id] ?? [],
                        providerOptions: providerOptions,
                        createdAt: service.createdAt
                    )
                )
            }

            return items
        }
    }

    public func fetchDeckItem(serviceID: UUID) async throws -> ServiceDeckItem? {
        try await dbWriter.read { db in
            guard let service = try Service.fetchOne(db, key: serviceID.uuidString) else { return nil }

            let providers = try Provider
                .filter(Column("serviceID") == serviceID.uuidString)
                .order(Column("createdAt").asc)
                .fetchAll(db)

            let portMappings = try ServicePortMapping
                .filter(Column("serviceID") == serviceID.uuidString)
                .fetchAll(db)

            let activeProvID = service.activeProviderID ?? providers.first?.id
            let activePorts = Self.localPortsForActiveProvider(
                mappings: portMappings,
                serviceID: service.id,
                activeProviderID: activeProvID
            )

            let memberships = try ServiceGroupMembershipRecord
                .filter(Column("serviceID") == serviceID.uuidString)
                .fetchAll(db)

            var category: ProviderCategory = .docker
            var resolvedTarget = ""

            if let activeProvID = service.activeProviderID,
               let provider = providers.first(where: { $0.id == activeProvID }) {
                category = provider.type
                resolvedTarget = provider.resolvedTarget
            } else if let firstProv = providers.first {
                category = firstProv.type
                resolvedTarget = firstProv.resolvedTarget
            }

            let groupIDs = Set(memberships.map(\.groupID))
            let activeID = activeProvID
            let providerOptions = providers.map { p in
                let rawLabel = p.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return ServiceDeckItem.DeckProviderOption(
                    id: p.id,
                    category: p.type,
                    label: rawLabel,
                    isActive: (p.id == activeID)
                )
            }

            return ServiceDeckItem(
                id: service.id,
                name: service.name,
                groupIDs: groupIDs,
                isDisabled: service.isDisabled,
                isStarred: service.isStarred,
                activeProviderCategory: category,
                resolvedTarget: resolvedTarget,
                serviceDescription: service.description,
                localPorts: activePorts,
                providerOptions: providerOptions,
                createdAt: service.createdAt
            )
        }
    }

    nonisolated static func portMappingsForActiveProvider(
        mappings: [ServicePortMapping],
        serviceID: UUID,
        activeProviderID: UUID?
    ) -> [ServicePortMapping] {
        guard let activeProviderID else { return [] }
        let scoped = mappings.filter { $0.serviceID == serviceID || $0.serviceID == nil }
        let forProvider = scoped.filter { $0.providerID == activeProviderID }
        if !forProvider.isEmpty {
            return forProvider
        }
        let legacy = scoped.filter { $0.providerID == nil }
        if legacy.count == scoped.count {
            return legacy
        }
        return []
    }

    private nonisolated static func localPortsForActiveProvider(
        mappings: [ServicePortMapping],
        serviceID: UUID,
        activeProviderID: UUID?
    ) -> [Int] {
        portMappingsForActiveProvider(
            mappings: mappings,
            serviceID: serviceID,
            activeProviderID: activeProviderID
        ).map(\.localPort)
    }
}
