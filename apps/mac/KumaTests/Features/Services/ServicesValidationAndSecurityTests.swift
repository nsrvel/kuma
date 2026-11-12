import Foundation
import Testing
import GRDB
@testable import Kuma

@Suite("Feature 06 - Category B: Services Validation, Crypto & Schema Security", .serialized)
@MainActor
struct ServicesValidationAndSecurityTests {

    // MARK: - [TC-B01] SSH Password Encrypted In Database
    @Test("TC-B01: SSH Password stored encrypted in SQLite and decrypted on fetch")
    func testSSHPasswordEncryptedInDatabase() async throws {
        let harness = ServicesTestHarness()
        let plainPassword = "SuperSecretSSHPassword123!"

        let (service, provider) = try await harness.seedServiceWithProvider(
            name: "SSH Server",
            providerType: .ssh,
            sshPassword: plainPassword
        )

        // 1. Verify raw value in SQLite column is NOT plaintext
        try await harness.databaseQueue.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT sshPassword FROM provider WHERE id = ?", arguments: [provider.id.uuidString])
            let rawInDb: String? = row?["sshPassword"]
            #expect(rawInDb != nil)
            #expect(rawInDb != plainPassword, "Raw password in SQLite must NOT be stored in plaintext")
            #expect(rawInDb!.contains(":"), "Ciphertext should be formatted as nonce:tag:ciphertext")
        }

        // 2. Verify repository fetch decodes and decrypts back to plain text
        let fetchedProviders = try await harness.serviceRepository.fetchProviders(forService: service.id)
        #expect(fetchedProviders.count == 1)
        #expect(fetchedProviders.first?.sshPassword == plainPassword)
    }

    // MARK: - [TC-B02] Ngrok Auth Token Encrypted In Database
    @Test("TC-B02: Ngrok Auth Token stored encrypted in SQLite and decrypted on fetch")
    func testNgrokTokenEncryptedInDatabase() async throws {
        let harness = ServicesTestHarness()
        let plainToken = "2Bxx_SecretNgrokTokenXYZ999"

        let (service, provider) = try await harness.seedServiceWithProvider(
            name: "Public Webhook Tunnel",
            providerType: .tunnel,
            ngrokAuthToken: plainToken
        )

        // 1. Verify raw value in SQLite column is encrypted
        try await harness.databaseQueue.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT ngrokAuthToken FROM provider WHERE id = ?", arguments: [provider.id.uuidString])
            let rawInDb: String? = row?["ngrokAuthToken"]
            #expect(rawInDb != nil)
            #expect(rawInDb != plainToken, "Raw token in SQLite must NOT be stored in plaintext")
            #expect(rawInDb!.contains(":"), "Ciphertext should be formatted as nonce:tag:ciphertext")
        }

        // 2. Verify repository fetch returns plain token
        let fetchedProviders = try await harness.serviceRepository.fetchProviders(forService: service.id)
        #expect(fetchedProviders.count == 1)
        #expect(fetchedProviders.first?.ngrokAuthToken == plainToken)
    }

    @Test("TC-B02b: Export backup JSON does not contain plaintext SSH password")
    func testExportBackupOmitsPlaintextPassword() async throws {
        let harness = ServicesTestHarness()
        let plainPassword = "ExportSecretPassword-unique-42"
        let (service, _) = try await harness.seedServiceWithProvider(
            name: "SSH Export",
            providerType: .ssh,
            sshPassword: plainPassword
        )

        let dataPort = DataPortRepository(dbWriter: harness.databaseQueue)
        let json = try await dataPort.exportSingleServiceJSON(serviceID: service.id)
        #expect(!json.contains(plainPassword))
        #expect(json.contains(":"), "Exported credentials should be vault ciphertext")
    }

    // MARK: - [TC-B03] Custom KubeConfig Path Persistence
    @Test("TC-B03: Custom KubeConfig Path persists in SQLite (Schema V4)")
    func testCustomKubeConfigPathPersistence() async throws {
        let harness = ServicesTestHarness()
        let customPath = "/Users/developer/.kube/staging-cluster.yaml"

        let (service, provider) = try await harness.seedServiceWithProvider(
            name: "Staging Cluster",
            providerType: .kubernetes,
            customKubeConfigPath: customPath
        )

        // 1. Verify raw column in SQLite exists and has custom path
        try await harness.databaseQueue.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT customKubeConfigPath FROM provider WHERE id = ?", arguments: [provider.id.uuidString])
            let rawPath: String? = row?["customKubeConfigPath"]
            #expect(rawPath == customPath)
        }

        // 2. Verify fetch preserves custom path
        let fetchedProviders = try await harness.serviceRepository.fetchProviders(forService: service.id)
        #expect(fetchedProviders.count == 1)
        #expect(fetchedProviders.first?.customKubeConfigPath == customPath)
    }

    // MARK: - [TC-B04] KubeConfig ID Materializes For kubectl
    @Test("TC-B04: Provider kubeConfigID resolves to on-disk kubeconfig for execution")
    func testKubeConfigIDMaterializesForExecution() async throws {
        let harness = ServicesTestHarness()
        let configID = UUID()
        let yaml = "apiVersion: v1\nkind: Config\n"
        let encrypted = try CryptoVault.shared.encrypt(plainText: yaml)
        let kubeRepo = KubeConfigRepository(dbWriter: harness.databaseQueue)
        try await kubeRepo.insert(
            KubeConfig(id: configID, name: "Staging", configContent: encrypted)
        )

        let provider = Provider(serviceID: UUID(), type: .kubernetes, kubeConfigID: configID)
        let path = try await KubeConfigMaterializer.kubectlKubeconfigPath(for: provider, repo: kubeRepo)
        #expect(path != nil)
        let content = try String(contentsOfFile: path!, encoding: .utf8)
        #expect(content.contains("apiVersion: v1"))
    }

    @Test("TC-B04d: kubeconfig sourceFilePath is used directly for kubectl")
    func testKubeConfigSourceFilePathUsedForExecution() async throws {
        let harness = ServicesTestHarness()
        let configID = UUID()
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("kuma-kube-\(UUID().uuidString).yaml")
        let yaml = "apiVersion: v1\nkind: Config\n"
        try yaml.write(to: fileURL, atomically: true, encoding: .utf8)

        let encryptedEmpty = try CryptoVault.shared.encrypt(plainText: "")
        let kubeRepo = KubeConfigRepository(dbWriter: harness.databaseQueue)
        try await kubeRepo.insert(
            KubeConfig(
                id: configID,
                name: "FileBacked",
                configContent: encryptedEmpty,
                sourceFilePath: fileURL.path
            )
        )

        let provider = Provider(serviceID: UUID(), type: .kubernetes, kubeConfigID: configID)
        let path = try await KubeConfigMaterializer.kubectlKubeconfigPath(for: provider, repo: kubeRepo)
        #expect(path == fileURL.path)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - [TC-B04b] Kube target name pattern matching
    @Test("TC-B04b: KubeTargetNameMatcher resolves wildcard and exact names")
    func testKubeTargetNameMatcher() {
        let names = ["mongo-svc-prod", "mongo-svc-staging", "redis-svc"]
        #expect(KubeTargetNameMatcher.firstMatch(pattern: "mongo-svc-*", in: names) == "mongo-svc-prod")
        #expect(KubeTargetNameMatcher.firstMatch(pattern: "redis-svc", in: names) == "redis-svc")
        #expect(KubeTargetNameMatcher.firstMatch(pattern: "missing-*", in: names) == nil)
    }

    @Test("TC-B04d: KubeTargetNameMatcher exact mode does not prefix-match")
    func testKubeTargetNameMatcherExactOnly() {
        let names = ["redis-svc-prod", "redis-svc"]
        #expect(KubeTargetNameMatcher.firstMatch(pattern: "redis-svc", in: names) == "redis-svc")
        #expect(KubeTargetNameMatcher.firstMatch(pattern: "redis", in: names) == nil)
    }

    @Test("TC-B04e: Pod pattern can match replica pod prefix")
    func testKubeTargetNameMatcherPodReplicaPrefix() {
        let pods = ["padiumkm-ms-product-7f8d9b2c3d-abcde", "other-pod"]
        #expect(
            KubeTargetNameMatcher.firstMatch(
                pattern: "padiumkm-ms-product",
                in: pods,
                allowPodReplicaPrefix: true
            ) == "padiumkm-ms-product-7f8d9b2c3d-abcde"
        )
        #expect(
            KubeTargetNameMatcher.firstMatch(
                pattern: "padiumkm-ms-product",
                in: pods,
                allowPodReplicaPrefix: false
            ) == nil
        )
    }

    @Test("TC-B04g: Pod pattern matches short deployment names and trailing hyphen")
    func testKubeTargetNameMatcherShortRedisDeployment() {
        let pods = ["redis-6bfd5bdc8-r2d8t", "unrelated-aaaaaaaabb-ccccc"]
        #expect(
            KubeTargetNameMatcher.firstMatch(
                pattern: "redis",
                in: pods,
                allowPodReplicaPrefix: true
            ) == "redis-6bfd5bdc8-r2d8t"
        )
        #expect(
            KubeTargetNameMatcher.firstMatch(
                pattern: "redis-",
                in: pods,
                allowPodReplicaPrefix: true
            ) == "redis-6bfd5bdc8-r2d8t"
        )
        #expect(KubeTargetNamingHints.looksLikeStableWorkloadName("redis") == true)
        #expect(KubeTargetNamingHints.replicaPodWorkloadStem(podName: "redis-6bfd5bdc8-r2d8t") == "redis")
    }

    @Test("TC-B04f: Pod pattern matches partial deployment stem before ReplicaSet hash")
    func testKubeTargetNameMatcherPartialDeploymentStem() {
        let pods = ["padiumkm-ms-masterdata-6cf68f49b4-qgdg7", "unrelated-aaaaaaaabb-ccccc"]
        #expect(
            KubeTargetNameMatcher.firstMatch(
                pattern: "padiumkm-ms-masterdata",
                in: pods,
                allowPodReplicaPrefix: true
            ) == "padiumkm-ms-masterdata-6cf68f49b4-qgdg7"
        )
        #expect(
            KubeTargetNameMatcher.firstMatch(
                pattern: "padiumkm-ms-master",
                in: pods,
                allowPodReplicaPrefix: true
            ) == "padiumkm-ms-masterdata-6cf68f49b4-qgdg7"
        )
    }

    @Test("Services.B04i: resolved kube target is runtime-only and does not mutate provider")
    func testKubeLiveTargetDisplayDoesNotPersistProvider() {
        let serviceID = UUID()
        let provider = Provider(
            serviceID: serviceID,
            type: .kubernetes,
            targetName: "redis-*",
            usePattern: true
        )
        KubeLiveTargetDisplay.setResolvedName("redis-master-0", for: serviceID)
        #expect(KubeLiveTargetDisplay.resolvedName(for: serviceID) == "redis-master-0")
        #expect(provider.targetName == "redis-*")
        #expect(provider.usePattern == true)
        KubeLiveTargetDisplay.clear(serviceID: serviceID)
        #expect(KubeLiveTargetDisplay.resolvedName(for: serviceID) == nil)
    }

    @Test("TC-B04h: kubectl port-forward adoption matches command line")
    func testKubePortForwardAdoptionMatching() {
        let plan = KubePortForwardPlan.Built(
            arguments: [
                "port-forward", "pod/my-app-pod", "19080:8080",
                "--kubeconfig", "/tmp/kube/config", "-n", "staging", "--context", "dev",
            ],
            localPorts: [19_080],
            kubectlReference: "pod/my-app-pod"
        )
        let command = "/opt/homebrew/bin/kubectl port-forward pod/my-app-pod 19080:8080 --kubeconfig /tmp/kube/config -n staging --context dev"
        #expect(KubePortForwardAdoption.matchesPortForward(commandLine: command, plan: plan))

        let wrongTarget = "/opt/homebrew/bin/kubectl port-forward pod/other 19080:8080 -n staging"
        #expect(!KubePortForwardAdoption.matchesPortForward(commandLine: wrongTarget, plan: plan))
    }

    @Test("TC-B04c: KubeTargetType maps to kubectl port-forward kinds")
    func testKubeTargetTypePortForwardKinds() {
        #expect(KubeTargetType.pod.portForwardKind == "pod")
        #expect(KubeTargetType.service.portForwardKind == "service")
        #expect(KubeTargetType.deployment.portForwardKind == "deployment")
        #expect(KubeTargetType.service.listResource == "services")
        #expect(KubeTargetType.deployment.listResource == "deployments")
    }

    // MARK: - [TC-B05a] Stale Kube Context Dropped At Runtime Parse
    @Test("TC-B05a: YAML parser drops stored context that is absent from kubeconfig file")
    func testYAMLParserDropsStaleProviderContext() {
        let yaml = """
        apiVersion: v1
        kind: Config
        current-context: staging
        contexts:
        - name: staging
          context:
            cluster: staging
        """
        #expect(KubeConfigYAMLParser.resolveContextName(stored: "c1-ins-abc-prod", in: yaml) == "staging")
    }

    // MARK: - [TC-B05c] Default kubeconfig row always present
    @Test("TC-B05c: Default kubeconfig row is always listed with resolved file path")
    func testDefaultKubeconfigRowAlwaysListed() async throws {
        let harness = ServicesTestHarness()
        let tempDir = FileManager.default.temporaryDirectory
        let kubeFile = tempDir.appendingPathComponent("kuma-kube-\(UUID().uuidString).yaml")
        try "apiVersion: v1\nkind: Config\n".write(to: kubeFile, atomically: true, encoding: .utf8)

        let suiteName = "TC-B05c-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(kubeFile.path, forKey: KumaSettingsKey.customKubeconfigPath)

        let vm = KubeConfigViewModel(
            repo: KubeConfigRepository(dbWriter: harness.databaseQueue),
            userDefaults: defaults
        )
        await vm.loadConfigs()

        let defaultRow = vm.availableKubeConfigs.first(where: { $0.id == KubeConfig.defaultID })
        #expect(defaultRow != nil)
        #expect(defaultRow?.isDefault == true)
        #expect(defaultRow?.sourceFilePath == kubeFile.path)
        try? FileManager.default.removeItem(at: kubeFile)
    }

    // MARK: - [TC-B05b] Stale Kube Context Dropped On Config Switch
    @Test("TC-B05b: Validation context resets when provider context is not in selected kubeconfig")
    func testResolvedValidationContextDropsStaleProviderContext() {
        let harness = ServicesTestHarness()
        let vm = KubeConfigViewModel(repo: KubeConfigRepository(dbWriter: harness.databaseQueue))
        let configID = UUID()
        let yaml = """
        current-context: staging
        contexts:
        - name: staging
        - name: prod
        """
        vm.availableKubeConfigs = [KubeConfig(id: configID, name: "Test", configContent: yaml)]
        vm.selectedKubeConfigID = configID

        #expect(vm.resolvedValidationContext(storedProviderContext: "docker-desktop") == "staging")
        #expect(vm.resolvedValidationContext(storedProviderContext: "prod") == "prod")
        #expect(vm.sanitizedProviderContext(storedProviderContext: "docker-desktop") == "staging")
    }

    // MARK: - [TC-B05] Inspector Persists Selected KubeConfig ID
    @Test("TC-B05: Inspector commit persists kubeConfigID from KubeConfigViewModel")
    func testInspectorPersistsSelectedKubeConfigID() async throws {
        let harness = ServicesTestHarness()
        let (service, _) = try await harness.seedServiceWithProvider(
            name: "K8s Service",
            providerType: .kubernetes
        )

        let selectedID = UUID()
        let encrypted = try CryptoVault.shared.encrypt(plainText: "apiVersion: v1\n")
        let kubeRepo = KubeConfigRepository(dbWriter: harness.databaseQueue)
        try await kubeRepo.insert(
            KubeConfig(id: selectedID, name: "Prod", configContent: encrypted)
        )

        let vm = ServiceInspectorViewModel(
            serviceID: service.id,
            workspaceID: harness.defaultWorkspaceID,
            serviceRepository: harness.serviceRepository
        )
        await vm.loadService(id: service.id)
        vm.kubeConfigVM = KubeConfigViewModel(repo: kubeRepo)
        await vm.kubeConfigVM?.loadConfigs(preferredSelectionID: selectedID)
        vm.kubeConfigVM?.selectedKubeConfigID = selectedID

        await vm.commitChanges()

        let providers = try await harness.serviceRepository.fetchProviders(forService: service.id)
        #expect(providers.first?.kubeConfigID == selectedID)
    }

    // MARK: - [TC-E01] Auto-Save Flushed On Disappear
    @Test("Services.E01: Inspector auto-save flush immediately persists changes")
    func testInspectorAutoSaveFlushImmediatelyPersists() async throws {
        let harness = ServicesTestHarness()
        let (service, provider) = try await harness.seedServiceWithProvider(
            name: "Initial Name",
            providerType: .shell
        )

        let vm = ServiceInspectorViewModel(
            serviceID: service.id,
            workspaceID: harness.defaultWorkspaceID,
            serviceRepository: harness.serviceRepository
        )
        await vm.loadService(id: service.id)

        // Modify in-memory state and schedule auto-save
        vm.service?.name = "Name Edited Right Before Close"
        vm.scheduleAutoSave()

        // Flush immediately without waiting for 300ms debounce
        await vm.flushPendingAutoSave()

        // Verify SQLite was updated
        let updated = try await harness.serviceRepository.fetchService(id: service.id)
        #expect(updated?.name == "Name Edited Right Before Close")
    }

    @Test("TC-E01b: Flush commits after debounce completed if user edits again before dismiss")
    func testInspectorFlushAfterDebounceCompleted() async throws {
        let harness = ServicesTestHarness()
        let (service, _) = try await harness.seedServiceWithProvider(
            name: "Rev Name",
            providerType: .shell
        )

        let vm = ServiceInspectorViewModel(
            serviceID: service.id,
            workspaceID: harness.defaultWorkspaceID,
            serviceRepository: harness.serviceRepository
        )
        await vm.loadService(id: service.id)

        vm.service?.name = "First Pass"
        vm.scheduleAutoSave()
        await vm.flushPendingAutoSave()

        vm.service?.name = "Second Pass Before Close"
        vm.scheduleAutoSave()
        await vm.flushPendingAutoSave()

        let updated = try await harness.serviceRepository.fetchService(id: service.id)
        #expect(updated?.name == "Second Pass Before Close")
    }

    // MARK: - [TC-RUN04] SSH auth type binding persists key vs password
    @Test("TC-RUN04: Inspector SSH auth type clears opposing credential on commit")
    func testInspectorSSHAuthTypeBinding() async throws {
        let harness = ServicesTestHarness()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("kuma-auth-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let keyURL = tempDir.appendingPathComponent("id_ed25519")
        try "key".write(to: keyURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (service, provider) = try await harness.seedServiceWithProvider(
            name: "SSH Auth",
            providerType: .ssh,
            sshKeyPath: keyURL.path,
            ports: [(2222, 22)]
        )

        let vm = ServiceInspectorViewModel(
            serviceID: service.id,
            workspaceID: harness.defaultWorkspaceID,
            serviceRepository: harness.serviceRepository
        )
        await vm.loadService(id: service.id)
        #expect(vm.sshAuthType == .key)

        vm.sshAuthType = .password
        ProviderSSHAuth.applyAuthTypeChange(.password, to: &vm.providers[0])
        vm.providers[0].sshPassword = "secret"
        await vm.commitChanges()

        let afterPassword = try await harness.serviceRepository.fetchProviders(forService: service.id).first
        #expect(afterPassword?.sshKeyPath == nil)
        #expect(afterPassword?.sshPassword == "secret")

        vm.sshAuthType = .key
        ProviderSSHAuth.applyAuthTypeChange(.key, to: &vm.providers[0])
        vm.providers[0].sshKeyPath = keyURL.path
        await vm.commitChanges()

        let afterKey = try await harness.serviceRepository.fetchProviders(forService: service.id).first
        #expect(afterKey?.sshPassword == nil)
        #expect(afterKey?.sshKeyPath == keyURL.path)
    }

    // MARK: - [TC-B06b] Kubeconfig not exported as plaintext YAML
    @Test("TC-B06b: DataPort kube export keeps YAML encrypted in backup JSON")
    func testDataPortKubeConfigNotPlaintext() async throws {
        let harness = ServicesTestHarness()
        let plainYAML = "apiVersion: v1\nkind: Config\nclusters:\n"
        let kubeID = UUID()
        let cipher = try CryptoVault.shared.encrypt(plainText: plainYAML)
        let kubeRepo = KubeConfigRepository(dbWriter: harness.databaseQueue)
        try await kubeRepo.insert(KubeConfig(id: kubeID, name: "Prod", configContent: cipher))

        let (service, _) = try await harness.seedServiceWithProvider(
            name: "K8s Prod",
            providerType: .kubernetes,
            kubeConfigID: kubeID,
            targetName: "api"
        )

        let dataPortRepo = DataPortRepository(dbWriter: harness.databaseQueue)
        let backup = try await dataPortRepo.exportData(scope: .service(service.id))

        let exportedKube = backup.kubeConfigs.first(where: { $0.id == kubeID })
        #expect(exportedKube != nil)
        #expect(exportedKube?.encryptedConfigContent == cipher)
        #expect(exportedKube?.encryptedConfigContent?.contains("apiVersion:") == false)
    }

    // MARK: - [TC-B08] Create K8s form validation
    @Test("TC-B08: Create Kubernetes form requires kubeconfig, context, ports, and target")
    func testCreateKubernetesFormValidation() {
        let baseInputs = CreateServiceDraftInputs(
            selectedProvider: .kubernetes,
            generalDraft: ServiceGeneralDraft(name: "DB"),
            kubeDraft: ServiceKubernetesDraft(
                context: "minikube",
                targetName: "postgres-svc"
            ),
            selectedKubeConfigID: KubeConfig.defaultID,
            dockerDraft: ServiceComposeDraft(),
            podmanDraft: ServiceComposeDraft(),
            shellDraft: ServiceShellDraft(),
            sshDraft: ServiceSSHDraft(),
            sshAuthType: .key,
            sshKeyPath: "",
            sshPassword: "",
            healthCheckDraft: ServiceHealthCheckDraft(),
            tunnelDraft: ServiceTunnelDraft(),
            monitorDraft: ServiceProcessMonitorDraft(),
            temporaryPorts: [KumaPortMappingItem(local: "5432", remote: "5432")]
        )
        #expect(CreateServicePayloadBuilder.isFormValid(inputs: baseInputs))

        let missingConfig = CreateServiceDraftInputs(
            selectedProvider: .kubernetes,
            generalDraft: ServiceGeneralDraft(name: "DB"),
            kubeDraft: ServiceKubernetesDraft(context: "minikube", targetName: "postgres-svc"),
            selectedKubeConfigID: nil,
            dockerDraft: ServiceComposeDraft(),
            podmanDraft: ServiceComposeDraft(),
            shellDraft: ServiceShellDraft(),
            sshDraft: ServiceSSHDraft(),
            sshAuthType: .key,
            sshKeyPath: "",
            sshPassword: "",
            healthCheckDraft: ServiceHealthCheckDraft(),
            tunnelDraft: ServiceTunnelDraft(),
            monitorDraft: ServiceProcessMonitorDraft(),
            temporaryPorts: [KumaPortMappingItem(local: "5432", remote: "5432")]
        )
        #expect(!CreateServicePayloadBuilder.isFormValid(inputs: missingConfig))

        let missingPort = CreateServiceDraftInputs(
            selectedProvider: .kubernetes,
            generalDraft: ServiceGeneralDraft(name: "DB"),
            kubeDraft: ServiceKubernetesDraft(context: "minikube", targetName: "postgres-svc"),
            selectedKubeConfigID: KubeConfig.defaultID,
            dockerDraft: ServiceComposeDraft(),
            podmanDraft: ServiceComposeDraft(),
            shellDraft: ServiceShellDraft(),
            sshDraft: ServiceSSHDraft(),
            sshAuthType: .key,
            sshKeyPath: "",
            sshPassword: "",
            healthCheckDraft: ServiceHealthCheckDraft(),
            tunnelDraft: ServiceTunnelDraft(),
            monitorDraft: ServiceProcessMonitorDraft(),
            temporaryPorts: [KumaPortMappingItem()]
        )
        #expect(!CreateServicePayloadBuilder.isFormValid(inputs: missingPort))
    }

    // MARK: - [TC-B06] DataPort Export Credential Encryption
    @Test("TC-B06: DataPort export keeps credentials protected and does not leak plaintext")
    func testDataPortExportCredentialEncryption() async throws {
        let harness = ServicesTestHarness()
        let secretPass = "TopSecretSSHKeyPassword999!"

        let (service, _) = try await harness.seedServiceWithProvider(
            name: "Secure SSH Host",
            providerType: .ssh,
            sshPassword: secretPass
        )

        let dataPortRepo = DataPortRepository(dbWriter: harness.databaseQueue)
        let backup = try await dataPortRepo.exportData(scope: .service(service.id))

        let exportedProv = backup.providers.first(where: { $0.serviceID == service.id })
        #expect(exportedProv != nil)
        #expect(exportedProv?.sshPassword != secretPass, "Exported backup JSON must not leak plain passwords")
    }
}
