import Foundation
import Testing
@testable import Kuma

@Suite("Kube target resolver matrix", .serialized)
struct KubeTargetResolverTests {

    private func makeProvider(
        targetName: String,
        targetType: KubeTargetType,
        usePattern: Bool
    ) -> Provider {
        Provider(
            serviceID: UUID(),
            type: .kubernetes,
            kubeNamespace: "staging",
            targetName: targetName,
            kubeTargetType: targetType.rawValue,
            usePattern: usePattern
        )
    }

    @Test("K1: pod exact port-forward reference")
    func testK1PodExact() async throws {
        let fixture = try KubectlTestFixture.install(script: KubectlTestScripts.noop)
        defer { fixture.cleanup() }
        let podName = "web-6cf68f49b4-abcde"
        let provider = makeProvider(targetName: podName, targetType: .pod, usePattern: false)
        let exec = KubeExecCredentials(kubeconfigPath: fixture.kubeconfig.path, context: nil)
        let resolved = try await KubeTargetResolver.resolve(provider: provider, kubectlPath: fixture.kubectlPath, exec: exec)
        #expect(resolved.kubectlReference == "pod/\(podName)")
    }

    @Test("K2: service exact")
    func testK2ServiceExact() async throws {
        let fixture = try KubectlTestFixture.install(script: KubectlTestScripts.noop)
        defer { fixture.cleanup() }
        let provider = makeProvider(targetName: "api-svc", targetType: .service, usePattern: false)
        let exec = KubeExecCredentials(kubeconfigPath: fixture.kubeconfig.path, context: nil)
        let resolved = try await KubeTargetResolver.resolve(provider: provider, kubectlPath: fixture.kubectlPath, exec: exec)
        #expect(resolved.kubectlReference == "service/api-svc")
    }

    @Test("K3: deployment exact")
    func testK3DeploymentExact() async throws {
        let fixture = try KubectlTestFixture.install(script: KubectlTestScripts.noop)
        defer { fixture.cleanup() }
        let provider = makeProvider(
            targetName: "forwarder-elasticsearch-stage",
            targetType: .deployment,
            usePattern: false
        )
        let exec = KubeExecCredentials(kubeconfigPath: fixture.kubeconfig.path, context: nil)
        let resolved = try await KubeTargetResolver.resolve(provider: provider, kubectlPath: fixture.kubectlPath, exec: exec)
        #expect(resolved.kubectlReference == "deployment/forwarder-elasticsearch-stage")
    }

    @Test("K4: service pattern lists and matches")
    func testK4ServicePattern() async throws {
        let listScript = """
        #!/bin/sh
        if [ "$1" = "get" ] && [ "$2" = "services" ]; then
          printf '%s\\n' 'beta-svc' 'api-svc-prod'
          exit 0
        fi
        exit 0
        """
        let fixture = try KubectlTestFixture.install(script: listScript)
        defer { fixture.cleanup() }
        let provider = makeProvider(targetName: "api-svc-*", targetType: .service, usePattern: true)
        let exec = KubeExecCredentials(kubeconfigPath: fixture.kubeconfig.path, context: nil)
        let resolved = try await KubeTargetResolver.resolve(provider: provider, kubectlPath: fixture.kubectlPath, exec: exec)
        #expect(resolved.kubectlReference == "service/api-svc-prod")
    }

    @Test("K5: deployment pattern exact name in list")
    func testK5DeploymentPattern() async throws {
        let listScript = """
        #!/bin/sh
        if [ "$1" = "get" ] && [ "$2" = "deployments" ]; then
          echo 'forwarder-elasticsearch-stage'
          exit 0
        fi
        exit 0
        """
        let fixture = try KubectlTestFixture.install(script: listScript)
        defer { fixture.cleanup() }
        let provider = makeProvider(
            targetName: "forwarder-elasticsearch-stage",
            targetType: .deployment,
            usePattern: true
        )
        let exec = KubeExecCredentials(kubeconfigPath: fixture.kubeconfig.path, context: nil)
        let resolved = try await KubeTargetResolver.resolve(provider: provider, kubectlPath: fixture.kubectlPath, exec: exec)
        #expect(resolved.kubectlReference == "deployment/forwarder-elasticsearch-stage")
    }

    @Test("K6: pod pattern uses running pod list")
    func testK6PodPattern() async throws {
        let listScript = """
        #!/bin/sh
        if [ "$1" = "get" ] && [ "$2" = "pods" ]; then
          echo 'app-pod-abc'
          exit 0
        fi
        exit 0
        """
        let fixture = try KubectlTestFixture.install(script: listScript)
        defer { fixture.cleanup() }
        let provider = makeProvider(targetName: "app-pod-abc", targetType: .pod, usePattern: true)
        let exec = KubeExecCredentials(kubeconfigPath: fixture.kubeconfig.path, context: nil)
        let resolved = try await KubeTargetResolver.resolve(provider: provider, kubectlPath: fixture.kubectlPath, exec: exec)
        #expect(resolved.kubectlReference == "pod/app-pod-abc")
    }
}
