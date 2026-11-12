import Foundation
import Testing
@testable import Kuma

@Suite("Service configuration validator")
@MainActor
struct ServiceConfigurationValidatorTests {
    @Test("K8s requires kubeconfig, context, target, and ports")
    func testKubernetesRequiredFields() {
        let service = Service(name: "api", workspaceID: UUID())
        let provider = Provider(id: UUID(), serviceID: service.id, type: .kubernetes)
        let context = ServiceConfigurationValidationContext(
            ports: [KumaPortMappingItem(local: "", remote: "")]
        )
        let issues = ServiceConfigurationValidator.issues(service: service, provider: provider, context: context)
        let codes = Set(issues.map(\.code))
        #expect(codes.contains("k8s.kubeconfig"))
        #expect(codes.contains("k8s.context"))
        #expect(codes.contains("k8s.target"))
        #expect(codes.contains("ports.required"))
    }

    @Test("Unreachable cluster is blocking")
    func testKubernetesUnreachable() {
        let service = Service(name: "api", workspaceID: UUID())
        var provider = Provider(id: UUID(), serviceID: service.id, type: .kubernetes)
        provider.targetName = "redis"
        provider.kubeContext = "staging"
        let context = ServiceConfigurationValidationContext(
            ports: [KumaPortMappingItem(local: "6379", remote: "6379")],
            kubeConfigID: UUID(),
            kubeContext: "staging",
            kubeConnectionError: "The cluster is not reachable."
        )
        let issues = ServiceConfigurationValidator.issues(service: service, provider: provider, context: context)
        #expect(issues.contains { $0.code == "k8s.unreachable" })
        #expect(ServiceConfigurationValidator.hasBlockingIssues(issues))
    }

    @Test("Shell requires command")
    func testShellCommand() {
        let service = Service(name: "job", workspaceID: UUID())
        let provider = Provider(id: UUID(), serviceID: service.id, type: .shell)
        let issues = ServiceConfigurationValidator.issues(
            service: service,
            provider: provider,
            context: ServiceConfigurationValidationContext()
        )
        #expect(issues.contains { $0.code == "shell.command" })
    }
}
