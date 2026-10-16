import SwiftUI

/// PERF-10: Keep runtime off grid parent; observe a single service execution state.
struct SyncedServiceRuntime: ViewModifier {
    let serviceID: UUID
    @Binding var runtime: ServiceRuntimeState

    func body(content: Content) -> some View {
        content
            .background {
                ServiceRuntimeObservationAnchor(serviceID: serviceID, runtime: $runtime)
            }
    }
}

private struct ServiceRuntimeObservationAnchor: View {
    let serviceID: UUID
    @Binding var runtime: ServiceRuntimeState
    @Environment(ServiceStateStore.self) private var serviceStateStore

    var body: some View {
        let executionState = serviceStateStore.state(for: serviceID)
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .onAppear { apply(executionState) }
            .onChange(of: executionState) { _, new in apply(new) }
    }

    private func apply(_ state: ServiceExecutionState) {
        let next = ServiceRuntimeState(executionState: state)
        if runtime != next {
            runtime = next
        }
    }
}

extension View {
    func syncingServiceRuntime(serviceID: UUID, runtime: Binding<ServiceRuntimeState>) -> some View {
        modifier(SyncedServiceRuntime(serviceID: serviceID, runtime: runtime))
    }
}
