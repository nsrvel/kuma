import Foundation
import Testing
@testable import Kuma

@Suite("Feature 05: Runners Execution Tests", .serialized)
struct RunnersExecutionTests {

    init() async {
        await ProcessTestSupport.resetProcessWorld()
    }

    @Test("TC-R01: ShellRunner executes command and captures output")
    func testShellRunnerExecution() async throws {
        let serviceID = UUID()
        let service = Service(id: serviceID, name: "Shell Test")
        let provider = Provider(serviceID: serviceID, type: .shell, runCommand: "echo 'Kuma Runner OK'")

        let runner = ShellRunner()

        try await runner.start(service: service, provider: provider)
        #expect(await runner.isRunning(serviceID: serviceID) == true)

        // Wait for process to finish
        try? await Task.sleep(nanoseconds: 200_000_000)
        await runner.stop(serviceID: serviceID)
        #expect(await runner.isRunning(serviceID: serviceID) == false)
    }

    @Test("TC-R02: ShellRunner rejects empty command")
    func testShellRunnerRejectsEmpty() async {
        let serviceID = UUID()
        let service = Service(id: serviceID, name: "Shell Empty")
        let provider = Provider(serviceID: serviceID, type: .shell, runCommand: "")

        let runner = ShellRunner()

        await #expect(throws: ServiceExecutionError.self) {
            try await runner.start(service: service, provider: provider)
        }
    }

    @Test("TC-R03: HealthCheckRunner start and clean stop lifecycle")
    func testHealthCheckLifecycle() async throws {
        let serviceID = UUID()
        let service = Service(id: serviceID, name: "Health Test")
        let provider = Provider(serviceID: serviceID, type: .httpCheck, httpCheckUrl: "google.com", httpCheckInterval: 5)

        let runner = HealthCheckRunner()

        try await runner.start(service: service, provider: provider)
        #expect(await runner.isRunning(serviceID: serviceID) == true)

        await runner.stop(serviceID: serviceID)
        #expect(await runner.isRunning(serviceID: serviceID) == false)
    }

    @Test("TC-R04: ProcessMonitorRunner start and clean stop lifecycle")
    func testProcessMonitorLifecycle() async throws {
        let serviceID = UUID()
        let service = Service(id: serviceID, name: "Monitor Test")
        let provider = Provider(serviceID: serviceID, type: .processMonitor, monitorProcessName: "launchd", monitorInterval: 3)

        let runner = ProcessMonitorRunner()

        try await runner.start(service: service, provider: provider)
        #expect(await runner.isRunning(serviceID: serviceID) == true)

        await runner.stop(serviceID: serviceID)
        #expect(await runner.isRunning(serviceID: serviceID) == false)
    }

    @Test("TC-R05: ShellRunner bootstraps user environment variables and PATH")
    func testShellRunnerEnvironmentBootstrapping() async throws {
        let serviceID = UUID()
        let service = Service(id: serviceID, name: "Env Test")
        let provider = Provider(serviceID: serviceID, type: .shell, runCommand: "which zsh")

        let runner = ShellRunner()

        try await runner.start(service: service, provider: provider)
        try? await Task.sleep(nanoseconds: 200_000_000)
        await runner.stop(serviceID: serviceID)
        #expect(await runner.isRunning(serviceID: serviceID) == false)
    }

    @Test("TC-R06: SSHTunnelRunner rejects empty host configuration")
    func testSSHTunnelRejectsEmptyHost() async {
        let serviceID = UUID()
        let service = Service(id: serviceID, name: "SSH Empty Host")
        let provider = Provider(serviceID: serviceID, type: .ssh, sshHost: "")

        let runner = SSHTunnelRunner(processLauncher: ProcessRegistryLauncher())

        await #expect(throws: ServiceExecutionError.self) {
            try await runner.start(service: service, provider: provider)
        }
    }

    @Test("TC-R07: SSHTunnelRunner cleans up temporary askpass script on stop")
    func testSSHTunnelCleanStopLifecycle() async throws {
        let serviceID = UUID()
        let runner = SSHTunnelRunner(processLauncher: ProcessRegistryLauncher())
        await runner.stop(serviceID: serviceID)
        #expect(await runner.isRunning(serviceID: serviceID) == false)
    }

    // MARK: - [TC-D05] Compose YAML written with -f flag (RUN-01)
    @Test("Runner.D05: ContainerRunner passes compose -f when yamlConfig is set")
    func testContainerRunnerComposeYamlWrite() async throws {
        let dockerKey = KumaSettingsKey.customDockerPath
        let priorDocker = UserDefaults.standard.string(forKey: dockerKey)
        UserDefaults.standard.set("/usr/bin/true", forKey: dockerKey)
        defer {
            if let priorDocker {
                UserDefaults.standard.set(priorDocker, forKey: dockerKey)
            } else {
                UserDefaults.standard.removeObject(forKey: dockerKey)
            }
        }

        let serviceID = UUID()
        let service = Service(id: serviceID, name: "Compose YAML")
        let yaml = "services:\n  web:\n    image: nginx:alpine\n"
        let provider = Provider(serviceID: serviceID, type: .docker, yamlConfig: yaml)

        let composeCLI = RecordingComposeCLI()
        let runner = ContainerRunner(processLauncher: RecordingProcessLaunching(), composeCLI: composeCLI)

        try await runner.start(service: service, provider: provider)

        let invocation = composeCLI.lastInvocation
        #expect(invocation != nil)
        #expect(invocation?.arguments == ContainerRunner.expectedUpArguments(
            composeFile: invocation!.context.composeFilePath,
            projectName: ComposeStackContext.projectName(for: serviceID)
        ))
        #expect(FileManager.default.fileExists(atPath: invocation!.context.composeFilePath))
        #expect(await runner.isRunning(serviceID: serviceID))

        await runner.stop(serviceID: serviceID)
        #expect(await runner.isRunning(serviceID: serviceID) == false)
    }

    @Test("Runner.D05b: ContainerRunner uses on-disk composeFilePath for docker")
    func testContainerRunnerComposeOnDiskPathDocker() async throws {
        let dockerKey = KumaSettingsKey.customDockerPath
        let priorDocker = UserDefaults.standard.string(forKey: dockerKey)
        UserDefaults.standard.set("/usr/bin/true", forKey: dockerKey)
        defer {
            if let priorDocker {
                UserDefaults.standard.set(priorDocker, forKey: dockerKey)
            } else {
                UserDefaults.standard.removeObject(forKey: dockerKey)
            }
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("kuma-compose-disk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let composeURL = tempDir.appendingPathComponent("docker-compose.yml")
        try "services:\n  web:\n    image: nginx:alpine\n".write(to: composeURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let serviceID = UUID()
        let service = Service(id: serviceID, name: "Compose On Disk")
        let provider = Provider(
            serviceID: serviceID,
            type: .docker,
            yamlConfig: "services:\n  stale:\n    image: redis\n",
            composeFilePath: composeURL.path
        )

        let composeCLI = RecordingComposeCLI()
        let runner = ContainerRunner(processLauncher: RecordingProcessLaunching(), composeCLI: composeCLI)

        try await runner.start(service: service, provider: provider)

        let invocation = composeCLI.lastInvocation
        #expect(invocation?.context.composeFilePath == composeURL.path)
        #expect(invocation?.context.workingDirectory == tempDir.path)
        #expect(invocation?.arguments.contains("-f") == true)
        #expect(invocation?.arguments.contains("-p") == true)

        await runner.stop(serviceID: serviceID, provider: provider)
        #expect(composeCLI.lastInvocation?.arguments.contains("down") == true)
        #expect(FileManager.default.fileExists(atPath: composeURL.path))
    }

    @Test("Runner.D05c: ContainerRunner uses on-disk composeFilePath for podman")
    func testContainerRunnerComposeOnDiskPathPodman() async throws {
        let podmanKey = KumaSettingsKey.customPodmanPath
        let priorPodman = UserDefaults.standard.string(forKey: podmanKey)
        UserDefaults.standard.set("/usr/bin/true", forKey: podmanKey)
        defer {
            if let priorPodman {
                UserDefaults.standard.set(priorPodman, forKey: podmanKey)
            } else {
                UserDefaults.standard.removeObject(forKey: podmanKey)
            }
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("kuma-compose-podman-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let composeURL = tempDir.appendingPathComponent("compose.yml")
        try "services:\n  api:\n    image: alpine\n".write(to: composeURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let serviceID = UUID()
        let service = Service(id: serviceID, name: "Podman On Disk")
        let provider = Provider(serviceID: serviceID, type: .podman, composeFilePath: composeURL.path)

        let composeCLI = RecordingComposeCLI()
        let runner = ContainerRunner(processLauncher: RecordingProcessLaunching(), composeCLI: composeCLI)

        try await runner.start(service: service, provider: provider)

        let invocation = composeCLI.lastInvocation
        #expect(invocation?.context.binaryPath == "/usr/bin/true")
        #expect(invocation?.context.composeFilePath == composeURL.path)

        await runner.stop(serviceID: serviceID)
    }

    @Test("Runner.D05d: ContainerRunner rejects missing compose file path")
    func testContainerRunnerMissingComposePath() async throws {
        let dockerKey = KumaSettingsKey.customDockerPath
        let priorDocker = UserDefaults.standard.string(forKey: dockerKey)
        UserDefaults.standard.set("/usr/bin/true", forKey: dockerKey)
        defer {
            if let priorDocker {
                UserDefaults.standard.set(priorDocker, forKey: dockerKey)
            } else {
                UserDefaults.standard.removeObject(forKey: dockerKey)
            }
        }

        let serviceID = UUID()
        let service = Service(id: serviceID, name: "Missing Compose")
        let provider = Provider(serviceID: serviceID, type: .docker, composeFilePath: "/no/such/compose.yml")

        let runner = ContainerRunner(
            processLauncher: RecordingProcessLaunching(),
            composeCLI: RecordingComposeCLI()
        )

        await #expect(throws: ServiceExecutionError.self) {
            try await runner.start(service: service, provider: provider)
        }
    }

    @Test("Runner.D05f: compose stack uses stable -p project name and -f file path")
    func testComposeStackContextArguments() {
        let serviceID = UUID()
        let path = "/tmp/deploy/prometheus.yml"
        let ctx = ComposeStackContext(
            serviceID: serviceID,
            binaryPath: "/usr/local/bin/docker",
            composeFilePath: path,
            workingDirectory: "/tmp/deploy",
            projectName: ComposeStackContext.projectName(for: serviceID),
            isEphemeralComposeFile: false
        )
        #expect(ctx.downArguments == [
            "compose", "-p", ctx.projectName, "-f", path,
            "down", "--timeout", "5", "--remove-orphans",
        ])
        #expect(ctx.upArguments.contains("-d"))
    }

    @Test("Runner.D05g: implicit default compose project omits -p")
    func testComposeStackImplicitDefaultArguments() {
        let serviceID = UUID()
        let path = "/tmp/deploy/docker-compose.yml"
        let ctx = ComposeStackContext(
            serviceID: serviceID,
            binaryPath: "/usr/local/bin/docker",
            composeFilePath: path,
            workingDirectory: "/tmp/deploy",
            projectName: ComposeStackContext.projectName(for: serviceID),
            isEphemeralComposeFile: false,
            projectBinding: .implicitDefault
        )
        #expect(ctx.downArguments == [
            "compose", "-f", path,
            "down", "--timeout", "5", "--remove-orphans",
        ])
        #expect(ctx.psQuietArgumentsImplicitDefault == ctx.psQuietArguments)
    }

    @Test("Runner.D05e: ContainerRunner runs startup script from initialScriptPath before compose")
    func testContainerRunnerInitialScriptPath() async throws {
        let dockerKey = KumaSettingsKey.customDockerPath
        let priorDocker = UserDefaults.standard.string(forKey: dockerKey)
        UserDefaults.standard.set("/usr/bin/true", forKey: dockerKey)
        defer {
            if let priorDocker {
                UserDefaults.standard.set(priorDocker, forKey: dockerKey)
            } else {
                UserDefaults.standard.removeObject(forKey: dockerKey)
            }
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("kuma-script-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let markerURL = tempDir.appendingPathComponent("ran.marker")
        let scriptURL = tempDir.appendingPathComponent("bootstrap.sh")
        try "#!/bin/sh\ntouch \"\(markerURL.path)\"\n".write(to: scriptURL, atomically: true, encoding: .utf8)
        let composeURL = tempDir.appendingPathComponent("docker-compose.yml")
        try "services:\n  web:\n    image: nginx:alpine\n".write(to: composeURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let serviceID = UUID()
        let service = Service(id: serviceID, name: "Script Path")
        let provider = Provider(
            serviceID: serviceID,
            type: .docker,
            composeFilePath: composeURL.path,
            initialScriptPath: scriptURL.path
        )

        let runner = ContainerRunner(
            processLauncher: RecordingProcessLaunching(),
            composeCLI: RecordingComposeCLI()
        )

        try await runner.start(service: service, provider: provider)
        #expect(FileManager.default.fileExists(atPath: markerURL.path))

        await runner.stop(serviceID: serviceID)
    }

    // MARK: - [TC-D06] SSH key path passed as -i (RUN-02)
    @Test("Runner.D06: SSHTunnelRunner includes -i for sshKeyPath")
    @MainActor
    func testSSHTunnelRunnerSSHKeyFlag() async throws {
        let harness = ServicesTestHarness()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("kuma-ssh-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let keyURL = tempDir.appendingPathComponent("id_test")
        try "fake-key".write(to: keyURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (service, provider) = try await harness.seedServiceWithProvider(
            name: "SSH Key",
            providerType: .ssh,
            sshKeyPath: keyURL.path,
            ports: [(8080, 80)]
        )

        var sshProvider = provider
        sshProvider.sshHost = "127.0.0.1"
        sshProvider.sshUser = "test"
        try await harness.serviceRepository.updateProvider(sshProvider)

        let recorder = RecordingProcessLaunching()
        let runner = SSHTunnelRunner(
            processLauncher: recorder,
            serviceRepository: harness.serviceRepository
        )

        try await runner.start(service: service, provider: sshProvider)

        let launch = recorder.lastLaunch
        #expect(launch?.executable == "/usr/bin/ssh")
        let args = launch?.arguments ?? []
        #expect(args.contains("-i"))
        let keyIndex = args.firstIndex(of: "-i")
        #expect(keyIndex != nil)
        #expect(args[keyIndex! + 1] == keyURL.path)

        await runner.stop(serviceID: service.id)
    }

    @Test("Runner.D08: KubernetesRunner launches port-forward with kubeconfig and namespace")
    @MainActor
    func testKubernetesRunnerPortForwardArgs() async throws {
        let fixture = try KubectlTestFixture.install(script: KubectlTestScripts.runningPodList("my-app-pod"))
        defer { fixture.cleanup() }

        let harness = ServicesTestHarness()
        let kubeconfigURL = fixture.kubeconfig

        let (service, provider) = try await harness.seedServiceWithProvider(
            name: "K8s Port Forward",
            providerType: .kubernetes,
            customKubeConfigPath: kubeconfigURL.path,
            targetName: "my-app-pod",
            ports: [(19_080, 8080)]
        )
        var k8sProvider = provider
        k8sProvider.usePattern = false
        k8sProvider.kubeNamespace = "staging"
        k8sProvider.kubeTargetType = KubeTargetType.pod.rawValue
        try await harness.serviceRepository.updateProvider(k8sProvider)

        let recorder = RecordingProcessLaunching()
        let runner = KubernetesRunner(
            processLauncher: recorder,
            serviceRepository: harness.serviceRepository
        )

        try await runner.start(service: service, provider: k8sProvider)

        let launch = recorder.lastLaunch
        #expect(launch?.executable == fixture.kubectlPath)
        let args = launch?.arguments ?? []
        #expect(args.first == "port-forward")
        #expect(args.contains("pod/my-app-pod"))
        #expect(args.contains("--kubeconfig"))
        #expect(args.contains(kubeconfigURL.path))
        #expect(args.contains("19080:8080"))
        #expect(args.contains("-n"))
        #expect(args.contains("staging"))
        #expect(await runner.isRunning(serviceID: service.id) == true)

        await runner.stop(serviceID: service.id)
        #expect(await runner.isRunning(serviceID: service.id) == false)
    }
}
