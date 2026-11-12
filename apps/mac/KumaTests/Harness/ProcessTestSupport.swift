import Foundation
@testable import Kuma

/// Serializes global process/supervisor resets across parallel test bundles.
actor ProcessTestIsolation {
    static let shared = ProcessTestIsolation()

    func resetProcessWorld() async {
        await ExecutionSupervisor.shared.stopAll()
        await ProcessRegistry.shared.terminateAllAsync()
    }
}

enum ProcessTestSupport {
    static func resetProcessWorld() async {
        KubeLiveTargetDisplay.clearAll()
        await AutoReconnectCoordinator.shared.resetForTests()
        await ProcessTestIsolation.shared.resetProcessWorld()
    }
}
