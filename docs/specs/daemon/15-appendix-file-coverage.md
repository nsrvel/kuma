# File Coverage Appendix

> Part of Kuma Daemon Spec ([15](15-traceability-and-parity.md)). Classifies every Swift file in `Kuma/` (1.x). **daemon** = reimplemented in Rust; **shared** = behavior moves to daemon, UI shell stays in client; **client-only** = presentation/platform, excluded from daemon parity (events/behavior noted).

Total files: 302

| # | File | Class | Spec | Note |
|---|------|-------|------|------|
| 1 | `Kuma/App/AppDelegate.swift` | shared | 14 | Quit flow UI stays client; teardown/auto-resume semantics in daemon |
| 2 | `Kuma/App/KumaCommands.swift` | client-only | - | Menus and shortcuts |
| 3 | `Kuma/App/KumaShortcuts.swift` | client-only | - | Menus and shortcuts |
| 4 | `Kuma/ContentView.swift` | client-only | - | App shell |
| 5 | `Kuma/Core/Audio/KumaSoundManager.swift` | client-only | 14 | Sound asset sync/playback; daemon only emits notification events |
| 6 | `Kuma/Core/Configuration/ConfigurationIssue.swift` | daemon | 05 | Validator and issue model |
| 7 | `Kuma/Core/Configuration/ServiceConfigurationValidator.swift` | daemon | 05 | Validator and issue model |
| 8 | `Kuma/Core/DataPort/DataPortService+BackupModels.swift` | daemon | 09 | Backup models, import/export, factory reset |
| 9 | `Kuma/Core/DataPort/DataPortService+FactoryReset.swift` | daemon | 09 | Backup models, import/export, factory reset |
| 10 | `Kuma/Core/DataPort/DataPortService+ImportExport.swift` | daemon | 09 | Backup models, import/export, factory reset |
| 11 | `Kuma/Core/DataPort/DataPortService.swift` | daemon | 09 | Backup models, import/export, factory reset |
| 12 | `Kuma/Core/Database/AppDatabase.swift` | daemon | 01 | Schema, migrations, pragmas, wipe |
| 13 | `Kuma/Core/Database/Records/KubeConfig+Record.swift` | daemon | 01 | GRDB record mapping; secret encrypt/decrypt |
| 14 | `Kuma/Core/Database/Records/Provider+Record.swift` | daemon | 01 | GRDB record mapping; secret encrypt/decrypt |
| 15 | `Kuma/Core/Database/Records/Service+Record.swift` | daemon | 01 | GRDB record mapping; secret encrypt/decrypt |
| 16 | `Kuma/Core/Database/Records/ServiceGroup+Record.swift` | daemon | 01 | GRDB record mapping; secret encrypt/decrypt |
| 17 | `Kuma/Core/Database/Records/ServiceGroupMembershipRecord.swift` | daemon | 01 | GRDB record mapping; secret encrypt/decrypt |
| 18 | `Kuma/Core/Database/Records/ServicePortMapping+Record.swift` | daemon | 01 | GRDB record mapping; secret encrypt/decrypt |
| 19 | `Kuma/Core/Database/Records/Workspace+Record.swift` | daemon | 01 | GRDB record mapping; secret encrypt/decrypt |
| 20 | `Kuma/Core/Database/Repositories/DataPortRepository+Export.swift` | daemon | 09 | Export/import persistence |
| 21 | `Kuma/Core/Database/Repositories/DataPortRepository+Import.swift` | daemon | 09 | Export/import persistence |
| 22 | `Kuma/Core/Database/Repositories/DataPortRepository+Mapping.swift` | daemon | 09 | Export/import persistence |
| 23 | `Kuma/Core/Database/Repositories/DataPortRepository.swift` | daemon | 09 | Export/import persistence |
| 24 | `Kuma/Core/Database/Repositories/KubeConfigRepository.swift` | daemon | 07 | Kubeconfig registry persistence |
| 25 | `Kuma/Core/Database/Repositories/ServiceGroupRepository.swift` | daemon | 04 | Workspace/group/service persistence and deck query |
| 26 | `Kuma/Core/Database/Repositories/ServiceRepository+CRUD.swift` | daemon | 04 | Workspace/group/service persistence and deck query |
| 27 | `Kuma/Core/Database/Repositories/ServiceRepository+DeckItems.swift` | daemon | 04 | Workspace/group/service persistence and deck query |
| 28 | `Kuma/Core/Database/Repositories/ServiceRepository.swift` | daemon | 04 | Workspace/group/service persistence and deck query |
| 29 | `Kuma/Core/Database/Repositories/WorkspaceRepository.swift` | daemon | 04 | Workspace/group/service persistence and deck query |
| 30 | `Kuma/Core/Environment/DependencyChecker.swift` | daemon | 03 | PATH resolution, dependency check, executable resolution, shell launch |
| 31 | `Kuma/Core/Environment/EnvironmentPathResolver.swift` | daemon | 03 | PATH resolution, dependency check, executable resolution, shell launch |
| 32 | `Kuma/Core/Environment/KumaSettingsExecutableResolver.swift` | daemon | 03 | PATH resolution, dependency check, executable resolution, shell launch |
| 33 | `Kuma/Core/Environment/KumaShellLaunchConfiguration.swift` | daemon | 03 | PATH resolution, dependency check, executable resolution, shell launch |
| 34 | `Kuma/Core/Execution/Compose/ComposeCLI.swift` | daemon | 06 | Execution engine |
| 35 | `Kuma/Core/Execution/Compose/ComposeStackContext.swift` | daemon | 06 | Execution engine |
| 36 | `Kuma/Core/Execution/Compose/ComposeStackResolver.swift` | daemon | 06 | Execution engine |
| 37 | `Kuma/Core/Execution/Compose/ComposeStackRuntime.swift` | daemon | 06 | Execution engine |
| 38 | `Kuma/Core/Execution/LocalPortConflictResolver.swift` | daemon | 06 | Execution engine |
| 39 | `Kuma/Core/Execution/Logging/ANSISanitizer.swift` | daemon | 08 | ANSI sanitizer, log entry, activity recording |
| 40 | `Kuma/Core/Execution/Logging/LiveLogEntry.swift` | daemon | 08 | ANSI sanitizer, log entry, activity recording |
| 41 | `Kuma/Core/Execution/Logging/SystemActivityLogRecording.swift` | daemon | 08 | ANSI sanitizer, log entry, activity recording |
| 42 | `Kuma/Core/Execution/PortConflictMessaging.swift` | daemon | 06 | Execution engine |
| 43 | `Kuma/Core/Execution/ProcessLaunching.swift` | daemon | 06 | Execution engine |
| 44 | `Kuma/Core/Execution/ProcessRegistry.swift` | daemon | 06 | Execution engine |
| 45 | `Kuma/Core/Execution/ProcessTreeTerminator.swift` | daemon | 06 | Execution engine |
| 46 | `Kuma/Core/Execution/Runners/ContainerRunner.swift` | daemon | 06 | Execution engine |
| 47 | `Kuma/Core/Execution/Runners/HealthCheckRunner.swift` | daemon | 06 | Execution engine |
| 48 | `Kuma/Core/Execution/Runners/KubernetesRunner.swift` | daemon | 06 | Execution engine |
| 49 | `Kuma/Core/Execution/Runners/ProcessMonitorRunner.swift` | daemon | 06 | Execution engine |
| 50 | `Kuma/Core/Execution/Runners/SSHTunnelRunner.swift` | daemon | 06 | Execution engine |
| 51 | `Kuma/Core/Execution/Runners/ServiceRunnerProtocol.swift` | daemon | 06 | Execution engine |
| 52 | `Kuma/Core/Execution/Runners/ShellRunner.swift` | daemon | 06 | Execution engine |
| 53 | `Kuma/Core/Execution/Runners/TunnelRunner.swift` | daemon | 06 | Execution engine |
| 54 | `Kuma/Core/Execution/ServiceExecutionEngine.swift` | daemon | 06 | Execution engine |
| 55 | `Kuma/Core/Execution/ServiceExecutionStateSync.swift` | daemon | 06 | Execution engine |
| 56 | `Kuma/Core/Execution/ServiceStartFailurePresenter.swift` | daemon | 06 | Execution engine |
| 57 | `Kuma/Core/Execution/ServiceStartSupport.swift` | daemon | 06 | Execution engine |
| 58 | `Kuma/Core/Execution/ServiceStopGate.swift` | daemon | 06 | Execution engine |
| 59 | `Kuma/Core/Execution/ServiceStopSupport.swift` | daemon | 06 | Execution engine |
| 60 | `Kuma/Core/Execution/Subprocess/EphemeralCLI.swift` | daemon | 06 | Execution engine |
| 61 | `Kuma/Core/Execution/SubprocessWait.swift` | daemon | 06 | Execution engine |
| 62 | `Kuma/Core/Execution/Supervision/AutoReconnectCoordinator.swift` | daemon | 06 | Execution engine |
| 63 | `Kuma/Core/Execution/Supervision/AutoReconnectPolicy.swift` | daemon | 06 | Execution engine |
| 64 | `Kuma/Core/Execution/Supervision/ExecutionModels.swift` | daemon | 06 | Execution engine |
| 65 | `Kuma/Core/Execution/Supervision/ExecutionSupervisor.swift` | daemon | 06 | Execution engine |
| 66 | `Kuma/Core/Execution/Supervision/RunSpool.swift` | daemon | 06 | Execution engine |
| 67 | `Kuma/Core/Haptics/KumaHapticManager.swift` | client-only | - | Trackpad haptics |
| 68 | `Kuma/Core/Kubernetes/KubeConfigExecutionResolver.swift` | daemon | 07 | Kubernetes support |
| 69 | `Kuma/Core/Kubernetes/KubeConfigMaterializer.swift` | daemon | 07 | Kubernetes support |
| 70 | `Kuma/Core/Kubernetes/KubeConfigYAMLParser.swift` | daemon | 07 | Kubernetes support |
| 71 | `Kuma/Core/Kubernetes/KubeConnectionValidator.swift` | daemon | 07 | Kubernetes support |
| 72 | `Kuma/Core/Kubernetes/KubeLiveTargetDisplay.swift` | daemon | 07 | Kubernetes support |
| 73 | `Kuma/Core/Kubernetes/KubePortForwardAdoption.swift` | daemon | 07 | Kubernetes support |
| 74 | `Kuma/Core/Kubernetes/KubePortForwardPlan.swift` | daemon | 07 | Kubernetes support |
| 75 | `Kuma/Core/Kubernetes/KubeTargetNameMatcher.swift` | daemon | 07 | Kubernetes support |
| 76 | `Kuma/Core/Kubernetes/KubeTargetNamingHints.swift` | daemon | 07 | Kubernetes support |
| 77 | `Kuma/Core/Kubernetes/KubeTargetResolver.swift` | daemon | 07 | Kubernetes support |
| 78 | `Kuma/Core/Lifecycle/AppCoordinator.swift` | client-only | 03 | Onboarding phase; persisted flag is a client pref in daemon KV |
| 79 | `Kuma/Core/Lifecycle/SingleInstanceGuard.swift` | shared | 14 | App guard stays client; daemon has own single-instance |
| 80 | `Kuma/Core/Notifications/AlertService.swift` | client-only | - | In-app modal |
| 81 | `Kuma/Core/Notifications/Notification+Kuma.swift` | client-only | 08 | Intra-app NotificationCenter names; mapped to daemon events |
| 82 | `Kuma/Core/Notifications/ServiceStateNotification.swift` | shared | 08 | State-change event shape and race guards |
| 83 | `Kuma/Core/Notifications/SystemNotificationCenter.swift` | shared | 14 | Daemon emits notify events; client shows UN banners |
| 84 | `Kuma/Core/Security/CredentialProtector.swift` | daemon | 02 | CryptoVault and CredentialProtector |
| 85 | `Kuma/Core/Security/CryptoVault.swift` | daemon | 02 | CryptoVault and CredentialProtector |
| 86 | `Kuma/Core/Storage/WorkspaceImageStore.swift` | daemon | 04 | Workspace image store |
| 87 | `Kuma/Domain/Enums/KubeTargetType.swift` | daemon | 07 | Kube target type |
| 88 | `Kuma/Domain/Enums/ProviderCategory.swift` | daemon | 01 | Domain model |
| 89 | `Kuma/Domain/Enums/ServiceEnums.swift` | shared | 06 | ServiceState enum |
| 90 | `Kuma/Domain/Enums/ServiceExecutionState.swift` | shared | 06 | Execution state enum |
| 91 | `Kuma/Domain/Models/KubeConfig.swift` | daemon | 01 | Domain model |
| 92 | `Kuma/Domain/Models/KumaSettingsKey.swift` | daemon | 03 | Setting keys and helpers |
| 93 | `Kuma/Domain/Models/Provider+KubernetesDefaults.swift` | daemon | 01 | Domain model |
| 94 | `Kuma/Domain/Models/Provider.swift` | daemon | 01 | Domain model |
| 95 | `Kuma/Domain/Models/Service.swift` | daemon | 01 | Domain model |
| 96 | `Kuma/Domain/Models/ServiceDeckItem.swift` | daemon | 04 | Deck read model |
| 97 | `Kuma/Domain/Models/ServiceGroup.swift` | daemon | 01 | Domain model |
| 98 | `Kuma/Domain/Models/ServicePortMapping.swift` | daemon | 01 | Domain model |
| 99 | `Kuma/Domain/Models/ServiceRuntimeState.swift` | shared | 06 | Runtime state wrapper |
| 100 | `Kuma/Domain/Models/SystemDependency.swift` | shared | 03 | Dependency scan model |
| 101 | `Kuma/Domain/Models/Workspace.swift` | daemon | 01 | Domain model |
| 102 | `Kuma/KumaApp.swift` | client-only | - | App shell |
| 103 | `Kuma/Lib/Extensions/NSApplication+Shared.swift` | client-only | - | macOS/UI helper |
| 104 | `Kuma/Lib/Extensions/UUID+Stable.swift` | daemon | 01 | Stable UUID (sidebar/provider ids) |
| 105 | `Kuma/Lib/Extensions/macOSSceneCompatibility.swift` | client-only | - | macOS/UI helper |
| 106 | `Kuma/Lib/KumaLinks.swift` | client-only | - | macOS/UI helper |
| 107 | `Kuma/Lib/KumaPortFormatting.swift` | client-only | - | macOS/UI helper |
| 108 | `Kuma/Lib/URLNormalizer.swift` | daemon | 05 | URL normalization |
| 109 | `Kuma/Presentation/Components/BrandVectors/DockerBrandVector.swift` | client-only | - | Reusable UI component |
| 110 | `Kuma/Presentation/Components/BrandVectors/KubernetesBrandVector.swift` | client-only | - | Reusable UI component |
| 111 | `Kuma/Presentation/Components/BrandVectors/NetworkVectors.swift` | client-only | - | Reusable UI component |
| 112 | `Kuma/Presentation/Components/BrandVectors/PodmanBrandVector.swift` | client-only | - | Reusable UI component |
| 113 | `Kuma/Presentation/Components/BrandVectors/ProviderBrandIcon.swift` | client-only | - | Reusable UI component |
| 114 | `Kuma/Presentation/Components/FinderDropTargetOverlay.swift` | client-only | - | Reusable UI component |
| 115 | `Kuma/Presentation/Components/FormKit/KumaCodeEditor.swift` | client-only | - | Reusable UI component |
| 116 | `Kuma/Presentation/Components/FormKit/KumaFileMetadata.swift` | client-only | - | Reusable UI component |
| 117 | `Kuma/Presentation/Components/FormKit/KumaFilePickerField.swift` | client-only | - | Reusable UI component |
| 118 | `Kuma/Presentation/Components/FormKit/KumaFormAddActionButton.swift` | client-only | - | Reusable UI component |
| 119 | `Kuma/Presentation/Components/FormKit/KumaFormCommitFooter.swift` | client-only | - | Reusable UI component |
| 120 | `Kuma/Presentation/Components/FormKit/KumaFormInlinePanel.swift` | client-only | - | Reusable UI component |
| 121 | `Kuma/Presentation/Components/FormKit/KumaFormSection.swift` | client-only | - | Reusable UI component |
| 122 | `Kuma/Presentation/Components/FormKit/KumaInspectorSegmentButton.swift` | client-only | - | Reusable UI component |
| 123 | `Kuma/Presentation/Components/FormKit/KumaNoticeBanner.swift` | client-only | - | Reusable UI component |
| 124 | `Kuma/Presentation/Components/FormKit/KumaOpenPanel.swift` | client-only | - | Reusable UI component |
| 125 | `Kuma/Presentation/Components/FormKit/KumaPortMappingEditor.swift` | client-only | - | Reusable UI component |
| 126 | `Kuma/Presentation/Components/FormKit/KumaRowPickerField.swift` | client-only | - | Reusable UI component |
| 127 | `Kuma/Presentation/Components/FormKit/KumaScriptFileSupport.swift` | client-only | - | Reusable UI component |
| 128 | `Kuma/Presentation/Components/FormKit/KumaSearchField.swift` | client-only | - | Reusable UI component |
| 129 | `Kuma/Presentation/Components/FormKit/KumaSecureField.swift` | client-only | - | Reusable UI component |
| 130 | `Kuma/Presentation/Components/FormKit/KumaSourceField.swift` | client-only | - | Reusable UI component |
| 131 | `Kuma/Presentation/Components/FormKit/KumaTextArea.swift` | client-only | - | Reusable UI component |
| 132 | `Kuma/Presentation/Components/FormKit/KumaTextField.swift` | client-only | - | Reusable UI component |
| 133 | `Kuma/Presentation/Components/FormKit/KumaToggleField.swift` | client-only | - | Reusable UI component |
| 134 | `Kuma/Presentation/Components/KumaCard.swift` | client-only | - | Reusable UI component |
| 135 | `Kuma/Presentation/Components/KumaDivider.swift` | client-only | - | Reusable UI component |
| 136 | `Kuma/Presentation/Components/KumaEmptyStateView.swift` | client-only | - | Reusable UI component |
| 137 | `Kuma/Presentation/Components/KumaGlobalAlertModifier.swift` | client-only | - | Reusable UI component |
| 138 | `Kuma/Presentation/Components/KumaPrimaryButton.swift` | client-only | - | Reusable UI component |
| 139 | `Kuma/Presentation/Components/Status/KumaStatusChip.swift` | client-only | - | Reusable UI component |
| 140 | `Kuma/Presentation/Components/Status/KumaToneWashBackground.swift` | client-only | - | Reusable UI component |
| 141 | `Kuma/Presentation/Components/Status/PortChipsView.swift` | client-only | - | Reusable UI component |
| 142 | `Kuma/Presentation/Components/Status/StatusPillView.swift` | client-only | - | Reusable UI component |
| 143 | `Kuma/Presentation/Components/WorkspaceAvatarView.swift` | client-only | - | Reusable UI component |
| 144 | `Kuma/Presentation/Features/DataPort/Models/ImportPreviewModels.swift` | client-only | 09 | Import preview UI; semantics in 09 |
| 145 | `Kuma/Presentation/Features/DataPort/Views/Components/FullImportTableView.swift` | client-only | 09 | Import preview UI; semantics in 09 |
| 146 | `Kuma/Presentation/Features/DataPort/Views/Components/ImportConfigurationSectionView.swift` | client-only | 09 | Import preview UI; semantics in 09 |
| 147 | `Kuma/Presentation/Features/DataPort/Views/Components/ImportDetailInspectorPane.swift` | client-only | 09 | Import preview UI; semantics in 09 |
| 148 | `Kuma/Presentation/Features/DataPort/Views/Components/ImportPortMappingsSectionView.swift` | client-only | 09 | Import preview UI; semantics in 09 |
| 149 | `Kuma/Presentation/Features/DataPort/Views/Components/ImportPortsBadgeView.swift` | client-only | 09 | Import preview UI; semantics in 09 |
| 150 | `Kuma/Presentation/Features/DataPort/Views/Components/ImportPreviewFooterView.swift` | client-only | 09 | Import preview UI; semantics in 09 |
| 151 | `Kuma/Presentation/Features/DataPort/Views/Components/ImportPreviewHeaderView.swift` | client-only | 09 | Import preview UI; semantics in 09 |
| 152 | `Kuma/Presentation/Features/DataPort/Views/Components/WorkspaceImportTableView.swift` | client-only | 09 | Import preview UI; semantics in 09 |
| 153 | `Kuma/Presentation/Features/DataPort/Views/ImportPreviewSheet.swift` | client-only | 09 | Import preview UI; semantics in 09 |
| 154 | `Kuma/Presentation/Features/DataPort/Views/WorkspaceImportPreviewSheet.swift` | client-only | 09 | Import preview UI; semantics in 09 |
| 155 | `Kuma/Presentation/Features/LiveLogs/ActivityLogFormatting.swift` | client-only | 08 | Log row formatting/style; categories defined in 08 |
| 156 | `Kuma/Presentation/Features/LiveLogs/ActivityLogStyle.swift` | client-only | 08 | Log row formatting/style; categories defined in 08 |
| 157 | `Kuma/Presentation/Features/LiveLogs/LiveLogRecordingBridge.swift` | shared | 08 | System log emission bridge |
| 158 | `Kuma/Presentation/Features/LiveLogs/LiveLogSession.swift` | shared | 08 | Activity buffer semantics |
| 159 | `Kuma/Presentation/Features/LiveLogs/LiveLogSourceRunner.swift` | shared | 08 | Workload log tail commands (V2-ADD) |
| 160 | `Kuma/Presentation/Features/LiveLogs/LiveLogSystemEmitter.swift` | shared | 08 | System log emission bridge |
| 161 | `Kuma/Presentation/Features/Onboarding/ViewModels/OnboardingViewModel.swift` | shared | 03 | Dependency scan + path validation |
| 162 | `Kuma/Presentation/Features/Onboarding/Views/Components/DependencyStatusRowView.swift` | client-only | 03 | Wizard UI |
| 163 | `Kuma/Presentation/Features/Onboarding/Views/OnboardingWizardView.swift` | client-only | 03 | Wizard UI |
| 164 | `Kuma/Presentation/Features/Onboarding/Views/Steps/ContainersAndClustersStepView.swift` | client-only | 03 | Wizard UI |
| 165 | `Kuma/Presentation/Features/Onboarding/Views/Steps/PublicTunnelingStepView.swift` | client-only | 03 | Wizard UI |
| 166 | `Kuma/Presentation/Features/Onboarding/Views/Steps/ReadyStepView.swift` | client-only | 03 | Wizard UI |
| 167 | `Kuma/Presentation/Features/Onboarding/Views/Steps/WelcomeStepView.swift` | client-only | 03 | Wizard UI |
| 168 | `Kuma/Presentation/Features/Services/Models/ProviderSSHAuth.swift` | shared | 05 | SSH auth normalization |
| 169 | `Kuma/Presentation/Features/Services/Models/ServiceCardSnapshot.swift` | shared | 04 | Deck snapshot + search key |
| 170 | `Kuma/Presentation/Features/Services/Models/ServiceInspectorDrafts.swift` | shared | 05 | Form draft defaults |
| 171 | `Kuma/Presentation/Features/Services/Models/ServicesDeckUIEnums.swift` | shared | 04 | Filter/sort enums |
| 172 | `Kuma/Presentation/Features/Services/ViewModels/KubeConfigViewModel.swift` | shared | 07 | Kubeconfig CRUD and validation logic |
| 173 | `Kuma/Presentation/Features/Services/ViewModels/ServiceInspectorViewModel+AutoSave.swift` | shared | 04 | Inspector edit/auto-save/provider ops |
| 174 | `Kuma/Presentation/Features/Services/ViewModels/ServiceInspectorViewModel+Execution.swift` | shared | 06 | Start/stop gating |
| 175 | `Kuma/Presentation/Features/Services/ViewModels/ServiceInspectorViewModel+Loading.swift` | shared | 04 | Inspector edit/auto-save/provider ops |
| 176 | `Kuma/Presentation/Features/Services/ViewModels/ServiceInspectorViewModel+Providers.swift` | shared | 04 | Inspector edit/auto-save/provider ops |
| 177 | `Kuma/Presentation/Features/Services/ViewModels/ServiceInspectorViewModel+Validation.swift` | shared | 05 | Preflight validation |
| 178 | `Kuma/Presentation/Features/Services/ViewModels/ServiceInspectorViewModel.swift` | shared | 04 | Inspector edit/auto-save/provider ops |
| 179 | `Kuma/Presentation/Features/Services/ViewModels/ServicesDeckViewModel+ExecutionActions.swift` | shared | 06 | Start/stop/restart/bulk |
| 180 | `Kuma/Presentation/Features/Services/ViewModels/ServicesDeckViewModel+Filtering.swift` | shared | 04 | Filter/sort/search |
| 181 | `Kuma/Presentation/Features/Services/ViewModels/ServicesDeckViewModel+ServiceActions.swift` | shared | 04 | Star/disable/duplicate/delete/groups/provider switch |
| 182 | `Kuma/Presentation/Features/Services/ViewModels/ServicesDeckViewModel+WorkspaceLoad.swift` | shared | 04 | Deck state and load |
| 183 | `Kuma/Presentation/Features/Services/ViewModels/ServicesDeckViewModel.swift` | shared | 04 | Deck state and load |
| 184 | `Kuma/Presentation/Features/Services/Views/CreateService/Components/CreateServiceComposeConfigurationSection.swift` | client-only | - | Services UI |
| 185 | `Kuma/Presentation/Features/Services/Views/CreateService/Components/CreateServiceContextualFormView.swift` | client-only | - | Services UI |
| 186 | `Kuma/Presentation/Features/Services/Views/CreateService/Components/CreateServiceDraftInputs.swift` | shared | 05 | Create payload/validation/defaults |
| 187 | `Kuma/Presentation/Features/Services/Views/CreateService/Components/CreateServicePayloadBuilder+ComposeDraft.swift` | shared | 05 | Create payload/validation/defaults |
| 188 | `Kuma/Presentation/Features/Services/Views/CreateService/Components/CreateServicePayloadBuilder.swift` | shared | 05 | Create payload/validation/defaults |
| 189 | `Kuma/Presentation/Features/Services/Views/CreateService/CreateServiceCreationDefaults.swift` | shared | 05 | Create payload/validation/defaults |
| 190 | `Kuma/Presentation/Features/Services/Views/CreateService/CreateServiceFillDetailsStepView.swift` | client-only | - | Services UI |
| 191 | `Kuma/Presentation/Features/Services/Views/CreateService/CreateServiceProviderStepView.swift` | client-only | - | Services UI |
| 192 | `Kuma/Presentation/Features/Services/Views/CreateService/CreateServiceSaving.swift` | shared | 05 | Create payload/validation/defaults |
| 193 | `Kuma/Presentation/Features/Services/Views/CreateService/CreateServiceSheet+KubeStep.swift` | client-only | - | Services UI |
| 194 | `Kuma/Presentation/Features/Services/Views/CreateService/CreateServiceSheet+Preview.swift` | client-only | - | Services UI |
| 195 | `Kuma/Presentation/Features/Services/Views/CreateService/CreateServiceSheet.swift` | client-only | - | Services UI |
| 196 | `Kuma/Presentation/Features/Services/Views/Deck/Components/CardToggleSwitch.swift` | client-only | - | Services UI |
| 197 | `Kuma/Presentation/Features/Services/Views/Deck/Components/ServiceActionContextMenu.swift` | client-only | - | Services UI |
| 198 | `Kuma/Presentation/Features/Services/Views/Deck/Components/ServiceCardContextMenu.swift` | client-only | - | Services UI |
| 199 | `Kuma/Presentation/Features/Services/Views/Deck/Components/ServiceCardRow.swift` | client-only | - | Services UI |
| 200 | `Kuma/Presentation/Features/Services/Views/Deck/Components/ServiceCardView.swift` | client-only | - | Services UI |
| 201 | `Kuma/Presentation/Features/Services/Views/Deck/Components/ServiceContextMenuSubmenus.swift` | client-only | - | Services UI |
| 202 | `Kuma/Presentation/Features/Services/Views/Deck/Components/ServiceDeckTableSection.swift` | client-only | - | Services UI |
| 203 | `Kuma/Presentation/Features/Services/Views/Deck/Components/ServiceNonPortBadge.swift` | client-only | - | Services UI |
| 204 | `Kuma/Presentation/Features/Services/Views/Deck/Components/ServiceStatusObserver.swift` | client-only | - | Services UI |
| 205 | `Kuma/Presentation/Features/Services/Views/Deck/Components/ServiceTableActionHandlers.swift` | client-only | - | Services UI |
| 206 | `Kuma/Presentation/Features/Services/Views/Deck/Components/ServiceTableColumns.swift` | client-only | - | Services UI |
| 207 | `Kuma/Presentation/Features/Services/Views/Deck/Components/ServiceTableContextMenuView.swift` | client-only | - | Services UI |
| 208 | `Kuma/Presentation/Features/Services/Views/Deck/Components/ServiceTableView.swift` | client-only | - | Services UI |
| 209 | `Kuma/Presentation/Features/Services/Views/Deck/Components/ServicesDeckCardGridView.swift` | client-only | - | Services UI |
| 210 | `Kuma/Presentation/Features/Services/Views/Deck/Components/ServicesDeckContentBodyView.swift` | client-only | - | Services UI |
| 211 | `Kuma/Presentation/Features/Services/Views/Deck/Components/ServicesToolbarMenus.swift` | client-only | - | Services UI |
| 212 | `Kuma/Presentation/Features/Services/Views/Deck/Components/SyncedServiceRuntime.swift` | client-only | - | Services UI |
| 213 | `Kuma/Presentation/Features/Services/Views/Deck/ServiceDeckActions.swift` | client-only | - | Services UI |
| 214 | `Kuma/Presentation/Features/Services/Views/Deck/ServicesDeckRuntimeObservation.swift` | client-only | - | Services UI |
| 215 | `Kuma/Presentation/Features/Services/Views/Deck/ServicesDeckView+DataPort.swift` | client-only | - | Services UI |
| 216 | `Kuma/Presentation/Features/Services/Views/Deck/ServicesDeckView+DeckChrome.swift` | client-only | - | Services UI |
| 217 | `Kuma/Presentation/Features/Services/Views/Deck/ServicesDeckView+Notifications.swift` | client-only | - | Services UI |
| 218 | `Kuma/Presentation/Features/Services/Views/Deck/ServicesDeckView.swift` | client-only | - | Services UI |
| 219 | `Kuma/Presentation/Features/Services/Views/Deck/ServicesToolbar.swift` | client-only | - | Services UI |
| 220 | `Kuma/Presentation/Features/Services/Views/Deck/WorkspaceServicesDeckHost.swift` | client-only | - | Services UI |
| 221 | `Kuma/Presentation/Features/Services/Views/Forms/ComposeSettingsView.swift` | client-only | - | Services UI |
| 222 | `Kuma/Presentation/Features/Services/Views/Forms/Docker/DockerComposeSettingsView.swift` | client-only | - | Services UI |
| 223 | `Kuma/Presentation/Features/Services/Views/Forms/Docker/InitialScriptSettingsView+Preview.swift` | client-only | - | Services UI |
| 224 | `Kuma/Presentation/Features/Services/Views/Forms/Docker/InitialScriptSettingsView.swift` | client-only | - | Services UI |
| 225 | `Kuma/Presentation/Features/Services/Views/Forms/General/ServiceGeneralSettingsView.swift` | client-only | - | Services UI |
| 226 | `Kuma/Presentation/Features/Services/Views/Forms/HealthCheck/HealthCheckSettingsView.swift` | client-only | - | Services UI |
| 227 | `Kuma/Presentation/Features/Services/Views/Forms/Kubernetes/Components/KubeConfigEditorExpandedContent.swift` | client-only | - | Services UI |
| 228 | `Kuma/Presentation/Features/Services/Views/Forms/Kubernetes/Components/KubeConfigFilePickerSupport.swift` | client-only | - | Services UI |
| 229 | `Kuma/Presentation/Features/Services/Views/Forms/Kubernetes/Components/KubeConfigInlineEditorView+Preview.swift` | client-only | - | Services UI |
| 230 | `Kuma/Presentation/Features/Services/Views/Forms/Kubernetes/Components/KubeConfigInlineEditorView.swift` | client-only | - | Services UI |
| 231 | `Kuma/Presentation/Features/Services/Views/Forms/Kubernetes/Components/KubeConfigItemRowView.swift` | client-only | - | Services UI |
| 232 | `Kuma/Presentation/Features/Services/Views/Forms/Kubernetes/KubeConfigConnectionView.swift` | client-only | - | Services UI |
| 233 | `Kuma/Presentation/Features/Services/Views/Forms/Kubernetes/KubeConnectionSettingsView.swift` | client-only | - | Services UI |
| 234 | `Kuma/Presentation/Features/Services/Views/Forms/Kubernetes/KubeTargetSettingsView.swift` | client-only | - | Services UI |
| 235 | `Kuma/Presentation/Features/Services/Views/Forms/Podman/PodmanComposeSettingsView.swift` | client-only | - | Services UI |
| 236 | `Kuma/Presentation/Features/Services/Views/Forms/Process/ProcessMonitorSettingsView.swift` | client-only | - | Services UI |
| 237 | `Kuma/Presentation/Features/Services/Views/Forms/SSH/SSHSettingsView.swift` | client-only | - | Services UI |
| 238 | `Kuma/Presentation/Features/Services/Views/Forms/Shell/ShellScriptSettingsView.swift` | client-only | - | Services UI |
| 239 | `Kuma/Presentation/Features/Services/Views/Forms/Tunnel/TunnelSettingsView.swift` | client-only | - | Services UI |
| 240 | `Kuma/Presentation/Features/Services/Views/Inspector/Components/InspectorComposeFormSection.swift` | client-only | - | Services UI |
| 241 | `Kuma/Presentation/Features/Services/Views/Inspector/Components/InspectorConfigFormStack.swift` | client-only | - | Services UI |
| 242 | `Kuma/Presentation/Features/Services/Views/Inspector/Components/InspectorHeaderActionButtons.swift` | client-only | - | Services UI |
| 243 | `Kuma/Presentation/Features/Services/Views/Inspector/Components/InspectorKubernetesFormSection.swift` | client-only | - | Services UI |
| 244 | `Kuma/Presentation/Features/Services/Views/Inspector/Components/InspectorLiveConsoleView.swift` | client-only | - | Services UI |
| 245 | `Kuma/Presentation/Features/Services/Views/Inspector/Components/InspectorRemoteAndNetworkFormSections.swift` | client-only | - | Services UI |
| 246 | `Kuma/Presentation/Features/Services/Views/Inspector/Components/InspectorRunningBanner.swift` | client-only | - | Services UI |
| 247 | `Kuma/Presentation/Features/Services/Views/Inspector/Components/InspectorStatusPillBanner+Preview.swift` | client-only | - | Services UI |
| 248 | `Kuma/Presentation/Features/Services/Views/Inspector/Components/InspectorStatusPillBanner.swift` | client-only | - | Services UI |
| 249 | `Kuma/Presentation/Features/Services/Views/Inspector/Components/ProviderItemRowView.swift` | client-only | - | Services UI |
| 250 | `Kuma/Presentation/Features/Services/Views/Inspector/Components/ServiceProvidersInlineFormView.swift` | client-only | - | Services UI |
| 251 | `Kuma/Presentation/Features/Services/Views/Inspector/Components/ServiceProvidersListView.swift` | client-only | - | Services UI |
| 252 | `Kuma/Presentation/Features/Services/Views/Inspector/Components/SystemActivityLogRow.swift` | client-only | - | Services UI |
| 253 | `Kuma/Presentation/Features/Services/Views/Inspector/InspectorFormSections.swift` | client-only | - | Services UI |
| 254 | `Kuma/Presentation/Features/Services/Views/Inspector/InspectorOptionsSection.swift` | client-only | - | Services UI |
| 255 | `Kuma/Presentation/Features/Services/Views/Inspector/InspectorStatusHeader.swift` | client-only | - | Services UI |
| 256 | `Kuma/Presentation/Features/Services/Views/Inspector/ServiceInspectorView.swift` | client-only | - | Services UI |
| 257 | `Kuma/Presentation/Features/Services/Views/Inspector/ServiceProvidersSectionView.swift` | client-only | - | Services UI |
| 258 | `Kuma/Presentation/Features/Settings/ViewModels/SettingsViewModel.swift` | shared | 03 | Settings logic |
| 259 | `Kuma/Presentation/Features/Settings/Views/Components/AppearanceCard.swift` | client-only | 03 | Settings UI |
| 260 | `Kuma/Presentation/Features/Settings/Views/Components/BinaryStatusBadge.swift` | client-only | 03 | Settings UI |
| 261 | `Kuma/Presentation/Features/Settings/Views/Components/SettingsDataPanelPresenter.swift` | client-only | 03 | Settings UI |
| 262 | `Kuma/Presentation/Features/Settings/Views/Sections/SettingsAppearanceSection.swift` | client-only | 03 | Settings UI |
| 263 | `Kuma/Presentation/Features/Settings/Views/Sections/SettingsCLIToolsSection.swift` | client-only | 03 | Settings UI |
| 264 | `Kuma/Presentation/Features/Settings/Views/Sections/SettingsDataSection.swift` | client-only | 03 | Settings UI |
| 265 | `Kuma/Presentation/Features/Settings/Views/Sections/SettingsGeneralSection.swift` | client-only | 03 | Settings UI |
| 266 | `Kuma/Presentation/Features/Settings/Views/Sections/SettingsPortsConnectionsSection.swift` | client-only | 03 | Settings UI |
| 267 | `Kuma/Presentation/Features/Settings/Views/Sections/SettingsTunnelingToolsSection.swift` | client-only | 03 | Settings UI |
| 268 | `Kuma/Presentation/Features/Settings/Views/SettingsView.swift` | client-only | 03 | Settings UI |
| 269 | `Kuma/Presentation/Features/Sidebar/Models/SidebarModel.swift` | shared | 04 | Sidebar tree and group logic |
| 270 | `Kuma/Presentation/Features/Sidebar/ViewModels/SidebarViewModel+FlattenedRows.swift` | shared | 04 | Sidebar tree and group logic |
| 271 | `Kuma/Presentation/Features/Sidebar/ViewModels/SidebarViewModel+Groups.swift` | shared | 04 | Sidebar tree and group logic |
| 272 | `Kuma/Presentation/Features/Sidebar/ViewModels/SidebarViewModel+Reorder.swift` | shared | 04 | Sidebar tree and group logic |
| 273 | `Kuma/Presentation/Features/Sidebar/ViewModels/SidebarViewModel.swift` | shared | 04 | Sidebar tree and group logic |
| 274 | `Kuma/Presentation/Features/Sidebar/Views/Components/GroupDragDropModifier.swift` | client-only | - | Sidebar UI |
| 275 | `Kuma/Presentation/Features/Sidebar/Views/Components/SidebarActionButton.swift` | client-only | - | Sidebar UI |
| 276 | `Kuma/Presentation/Features/Sidebar/Views/Components/SidebarChevron.swift` | client-only | - | Sidebar UI |
| 277 | `Kuma/Presentation/Features/Sidebar/Views/Components/SidebarDropIndicator.swift` | client-only | - | Sidebar UI |
| 278 | `Kuma/Presentation/Features/Sidebar/Views/Components/SidebarEmptyPlaceholderRow.swift` | client-only | - | Sidebar UI |
| 279 | `Kuma/Presentation/Features/Sidebar/Views/Components/SidebarFooterButton.swift` | client-only | - | Sidebar UI |
| 280 | `Kuma/Presentation/Features/Sidebar/Views/Components/SidebarFooterView.swift` | client-only | - | Sidebar UI |
| 281 | `Kuma/Presentation/Features/Sidebar/Views/Components/SidebarRowActionButtons.swift` | client-only | - | Sidebar UI |
| 282 | `Kuma/Presentation/Features/Sidebar/Views/Components/SidebarRowIcon.swift` | client-only | - | Sidebar UI |
| 283 | `Kuma/Presentation/Features/Sidebar/Views/Components/SidebarRowInlineEditor.swift` | client-only | - | Sidebar UI |
| 284 | `Kuma/Presentation/Features/Sidebar/Views/Components/SidebarRowView.swift` | client-only | - | Sidebar UI |
| 285 | `Kuma/Presentation/Features/Sidebar/Views/SidebarView.swift` | client-only | - | Sidebar UI |
| 286 | `Kuma/Presentation/Features/Workspace/Views/Components/InactiveWorkspaceRow.swift` | client-only | 04 | Workspace UI; rules in 04 |
| 287 | `Kuma/Presentation/Features/Workspace/Views/Components/NewWorkspaceBottomButton.swift` | client-only | 04 | Workspace UI; rules in 04 |
| 288 | `Kuma/Presentation/Features/Workspace/Views/Components/WorkspaceAvatarBadges.swift` | client-only | 04 | Workspace UI; rules in 04 |
| 289 | `Kuma/Presentation/Features/Workspace/Views/Components/WorkspaceAvatarPickerView.swift` | client-only | 04 | Workspace UI; rules in 04 |
| 290 | `Kuma/Presentation/Features/Workspace/Views/Components/WorkspaceFormDeleteRow.swift` | client-only | 04 | Workspace UI; rules in 04 |
| 291 | `Kuma/Presentation/Features/Workspace/Views/SidebarWorkspaceRow.swift` | client-only | 04 | Workspace UI; rules in 04 |
| 292 | `Kuma/Presentation/Features/Workspace/Views/WorkspaceFormSheet.swift` | client-only | 04 | Workspace UI; rules in 04 |
| 293 | `Kuma/Presentation/Features/Workspace/Views/WorkspaceSwitcherPopover.swift` | client-only | 04 | Workspace UI; rules in 04 |
| 294 | `Kuma/Presentation/Theme/AccessibilityIdentifiers.swift` | client-only | - | Theme tokens |
| 295 | `Kuma/Presentation/Theme/KumaLogFont.swift` | client-only | - | Theme tokens |
| 296 | `Kuma/Presentation/Theme/KumaStatus.swift` | client-only | - | Theme tokens |
| 297 | `Kuma/Presentation/Theme/KumaTheme.swift` | client-only | - | Theme tokens |
| 298 | `Kuma/Presentation/Theme/ProviderCategory+Theme.swift` | client-only | - | Theme tokens |
| 299 | `Kuma/Presentation/Theme/ServiceState+Theme.swift` | client-only | - | Theme tokens |
| 300 | `Kuma/Stores/ServiceStateStore+Supervisor.swift` | shared | 06 | Runtime state cache; daemon owns truth |
| 301 | `Kuma/Stores/ServiceStateStore.swift` | shared | 06 | Runtime state cache; daemon owns truth |
| 302 | `Kuma/Stores/WorkspaceStore.swift` | shared | 04 | Workspace state and rules move to daemon; selection pref is client KV |

Summary: client-only=172, daemon=87, shared=43
