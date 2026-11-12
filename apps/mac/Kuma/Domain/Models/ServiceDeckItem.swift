import Foundation

/// Domain projection for deck/list rows (no Presentation-only fields such as `searchKey`).
public nonisolated struct ServiceDeckItem: Identifiable, Sendable, Equatable, Hashable {
    public nonisolated struct DeckProviderOption: Identifiable, Sendable, Equatable, Hashable {
        public let id: UUID
        public let category: ProviderCategory
        /// Raw label from DB; empty when unset (Presentation may apply category fallback).
        public let label: String
        public let isActive: Bool

        public nonisolated init(id: UUID, category: ProviderCategory, label: String, isActive: Bool) {
            self.id = id
            self.category = category
            self.label = label
            self.isActive = isActive
        }
    }

    public let id: UUID
    public let name: String
    public let groupIDs: Set<UUID>
    public let isDisabled: Bool
    public var isStarred: Bool
    public let activeProviderCategory: ProviderCategory
    /// Provider `resolvedTarget` when an active/first provider exists.
    public let resolvedTarget: String
    public let serviceDescription: String?
    public let localPorts: [Int]
    public let providerOptions: [DeckProviderOption]
    public let createdAt: Date

    public nonisolated init(
        id: UUID,
        name: String,
        groupIDs: Set<UUID> = [],
        isDisabled: Bool = false,
        isStarred: Bool = false,
        activeProviderCategory: ProviderCategory = .docker,
        resolvedTarget: String = "",
        serviceDescription: String? = nil,
        localPorts: [Int] = [],
        providerOptions: [DeckProviderOption] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.groupIDs = groupIDs
        self.isDisabled = isDisabled
        self.isStarred = isStarred
        self.activeProviderCategory = activeProviderCategory
        self.resolvedTarget = resolvedTarget
        self.serviceDescription = serviceDescription
        self.localPorts = localPorts
        self.providerOptions = providerOptions
        self.createdAt = createdAt
    }

    public func toggling(starred: Bool) -> Self {
        var copy = self
        copy.isStarred = starred
        return copy
    }
}
