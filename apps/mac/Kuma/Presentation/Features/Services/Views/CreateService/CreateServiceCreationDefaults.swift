import Foundation

/// Sidebar context applied when saving a newly created service.
public struct CreateServiceCreationDefaults: Sendable, Equatable {
    public var starOnCreate: Bool
    public var initialGroupID: UUID?

    public init(starOnCreate: Bool = false, initialGroupID: UUID? = nil) {
        self.starOnCreate = starOnCreate
        self.initialGroupID = initialGroupID
    }
}
