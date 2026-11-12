import SwiftUI
import os

public struct CreateServiceSheet: View {
    private static let logger = Logger(subsystem: "lokastudio.kuma", category: "CreateServiceSheet")

    public let workspaceID: UUID
    public let creationDefaults: CreateServiceCreationDefaults
    private let serviceRepository: any ServiceRepositoryProtocol
    public var onServiceCreated: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    public enum CreationStep {
        case selectProvider
        case fillDetails
    }

    @State var currentStep: CreationStep = .selectProvider
    @State var selectedProvider: ProviderCategory = .kubernetes

    // Grouped Form Drafts
    @State private var generalDraft = ServiceGeneralDraft()
    @State private var kubeDraft = ServiceKubernetesDraft()
    @State var kubeConfigVM = KubeConfigViewModel()
    @State private var dockerDraft = ServiceComposeDraft()
    @State private var podmanDraft = ServiceComposeDraft()
    @State private var shellDraft = ServiceShellDraft()
    @State private var sshDraft = ServiceSSHDraft()
    @State private var sshAuthType: SSHAuthType = .key
    @State private var sshKeyPath: String = "~/.ssh/id_ed25519"
    @State private var sshPassword: String = ""
    @State private var healthCheckDraft = ServiceHealthCheckDraft()
    @State private var tunnelDraft = ServiceTunnelDraft()
    @State private var monitorDraft = ServiceProcessMonitorDraft()
    @State private var temporaryPorts: [KumaPortMappingItem] = [KumaPortMappingItem()]
    @State private var isSaving: Bool = false

    public init(
        workspaceID: UUID,
        creationDefaults: CreateServiceCreationDefaults = CreateServiceCreationDefaults(),
        serviceRepository: any ServiceRepositoryProtocol = ServiceRepository(),
        onServiceCreated: (() -> Void)? = nil
    ) {
        self.workspaceID = workspaceID
        self.creationDefaults = creationDefaults
        self.serviceRepository = serviceRepository
        self.onServiceCreated = onServiceCreated
    }

    private var currentDraftInputs: CreateServicePayloadBuilder.DraftInputs {
        CreateServicePayloadBuilder.DraftInputs(
            selectedProvider: selectedProvider,
            generalDraft: generalDraft,
            kubeDraft: kubeDraft,
            selectedKubeConfigID: kubeConfigVM.selectedKubeConfigID,
            dockerDraft: dockerDraft,
            podmanDraft: podmanDraft,
            shellDraft: shellDraft,
            sshDraft: sshDraft,
            sshAuthType: sshAuthType,
            sshKeyPath: sshKeyPath,
            sshPassword: sshPassword,
            healthCheckDraft: healthCheckDraft,
            tunnelDraft: tunnelDraft,
            monitorDraft: monitorDraft,
            temporaryPorts: temporaryPorts
        )
    }

    private var isFormValid: Bool {
        CreateServicePayloadBuilder.isFormValid(inputs: currentDraftInputs)
    }

    public var body: some View {
        VStack(spacing: 0) {
            switch currentStep {
            case .selectProvider:
                CreateServiceProviderStepView(
                    selectedProvider: $selectedProvider,
                    onContinue: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            currentStep = .fillDetails
                        }
                    },
                    onCancel: { dismiss() }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            case .fillDetails:
                CreateServiceFillDetailsStepView(
                    selectedProvider: selectedProvider,
                    generalDraft: $generalDraft,
                    kubeDraft: $kubeDraft,
                    kubeConfigVM: kubeConfigVM,
                    dockerDraft: $dockerDraft,
                    podmanDraft: $podmanDraft,
                    shellDraft: $shellDraft,
                    sshDraft: $sshDraft,
                    sshAuthType: $sshAuthType,
                    sshKeyPath: $sshKeyPath,
                    sshPassword: $sshPassword,
                    healthCheckDraft: $healthCheckDraft,
                    tunnelDraft: $tunnelDraft,
                    monitorDraft: $monitorDraft,
                    temporaryPorts: $temporaryPorts,
                    isFormValid: isFormValid,
                    isSaving: isSaving,
                    onBack: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            currentStep = .selectProvider
                        }
                    },
                    onCancel: { dismiss() },
                    onCreate: { beginCreateService() }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: currentStep)
        .onChange(of: currentStep) { _, step in loadKubeConfigsWhenEnteringDetails(step: step) }
        .frame(
            width: currentStep == .selectProvider ? 520 : 500,
            height: currentStep == .selectProvider ? 440 : 580
        )
    }

    private func beginCreateService() {
        isSaving = true
        if selectedProvider == .kubernetes {
            let stored = kubeDraft.context.isEmpty ? nil : kubeDraft.context
            if let sanitized = kubeConfigVM.sanitizedProviderContext(storedProviderContext: stored) {
                kubeDraft.context = sanitized
            }
        }
        CreateServiceSaving.beginCreate(
            workspaceID: workspaceID,
            inputs: currentDraftInputs,
            creationDefaults: creationDefaults,
            serviceRepository: serviceRepository,
            onServiceCreated: onServiceCreated,
            dismiss: { dismiss() },
            onSavingFailed: { isSaving = false }
        )
    }
}
