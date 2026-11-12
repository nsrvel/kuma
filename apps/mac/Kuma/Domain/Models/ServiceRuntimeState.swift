import Foundation

/// Fast and lightweight runtime state container that holds frequent live updates.
/// Kept strictly isolated from static metadata so status changes only invalidate micro-observers.
public struct ServiceRuntimeState: Sendable, Equatable {
    public var status: ServiceState
    public var isLoading: Bool
    public var statusTitle: String

    /// Shared zero-allocation default for dictionary miss lookups
    public static let idle = ServiceRuntimeState()

    public init(
        status: ServiceState = .stopped,
        isLoading: Bool = false,
        statusTitle: String? = nil
    ) {
        self.status = status
        self.isLoading = isLoading
        self.statusTitle = statusTitle ?? status.title
    }

    /// Convenience initializer bridging from discrete ServiceExecutionState
    public init(executionState: ServiceExecutionState) {
        self.status = executionState.legacyState
        self.isLoading = executionState.isLoading
        self.statusTitle = executionState.title
    }
}
