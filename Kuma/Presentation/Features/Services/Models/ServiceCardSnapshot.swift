import Foundation

/// Presentation DTO for deck cards and table rows (mapped from `ServiceDeckItem`).
public nonisolated struct ServiceCardSnapshot: Identifiable, Sendable, Equatable, Hashable {
    public nonisolated struct ProviderOption: Identifiable, Sendable, Equatable, Hashable {
        public let id: UUID
        public let category: ProviderCategory
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
    public let subtitle: String
    public let providerCategory: ProviderCategory
    public let portDisplays: [Int]
    public let providerOptions: [ProviderOption]
    public let createdAt: Date
    public let searchKey: String

    public nonisolated init(
        id: UUID,
        name: String,
        groupIDs: Set<UUID> = [],
        isDisabled: Bool = false,
        isStarred: Bool = false,
        subtitle: String = "",
        providerCategory: ProviderCategory = .shell,
        portDisplays: [Int] = [],
        providerOptions: [ProviderOption] = [],
        createdAt: Date = Date(),
        searchKey: String? = nil
    ) {
        self.id = id
        self.name = name
        self.groupIDs = groupIDs
        self.isDisabled = isDisabled
        self.isStarred = isStarred
        self.subtitle = subtitle
        self.providerCategory = providerCategory
        self.portDisplays = portDisplays
        self.providerOptions = providerOptions
        self.createdAt = createdAt
        self.searchKey = (searchKey ?? "\(name) \(subtitle)").lowercased()
    }

    public func toggling(starred: Bool) -> Self {
        var copy = self
        copy.isStarred = starred
        return copy
    }

    /// Case-insensitive substring match against indexed fields and live Kubernetes target names.
    public nonisolated func matchesSearchQuery(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return true }
        if searchKey.contains(trimmed) { return true }
        if providerCategory == .kubernetes,
           let live = KubeLiveTargetDisplay.resolvedName(for: id)?.lowercased(),
           live.contains(trimmed) {
            return true
        }
        return false
    }
}

extension ServiceCardSnapshot {
    public nonisolated init(deckItem: ServiceDeckItem) {
        let subtitle: String = {
            if let desc = deckItem.serviceDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                return desc
            }
            let target = deckItem.resolvedTarget.trimmingCharacters(in: .whitespacesAndNewlines)
            if !target.isEmpty { return target }
            return ""
        }()

        let options = deckItem.providerOptions.map { opt in
            let trimmed = opt.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = trimmed.isEmpty ? opt.category.sidebarLabel : trimmed
            return ProviderOption(
                id: opt.id,
                category: opt.category,
                label: label,
                isActive: opt.isActive
            )
        }

        self.init(
            id: deckItem.id,
            name: deckItem.name,
            groupIDs: deckItem.groupIDs,
            isDisabled: deckItem.isDisabled,
            isStarred: deckItem.isStarred,
            subtitle: subtitle,
            providerCategory: deckItem.activeProviderCategory,
            portDisplays: deckItem.localPorts,
            providerOptions: options,
            createdAt: deckItem.createdAt,
            searchKey: Self.deckSearchKey(for: deckItem)
        )
    }

    private nonisolated static func deckSearchKey(for item: ServiceDeckItem) -> String {
        var parts: [String] = [item.name.trimmingCharacters(in: .whitespacesAndNewlines)]
        if let desc = item.serviceDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
            parts.append(desc)
        }
        let target = item.resolvedTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        if !target.isEmpty { parts.append(target) }
        parts.append(item.activeProviderCategory.sidebarLabel)
        for opt in item.providerOptions {
            let trimmed = opt.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { parts.append(trimmed) }
        }
        for port in item.localPorts {
            parts.append(String(port))
        }
        return parts.joined(separator: " ").lowercased()
    }
}

extension Array where Element == ServiceDeckItem {
    public var asCardSnapshots: [ServiceCardSnapshot] {
        map { ServiceCardSnapshot(deckItem: $0) }
    }
}
