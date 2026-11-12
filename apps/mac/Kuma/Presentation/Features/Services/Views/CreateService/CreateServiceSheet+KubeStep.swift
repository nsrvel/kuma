import SwiftUI

extension CreateServiceSheet {
    func loadKubeConfigsWhenEnteringDetails(step: CreationStep) {
        guard step == .fillDetails, selectedProvider == .kubernetes else { return }
        Task { await kubeConfigVM.loadConfigs(preferredSelectionID: kubeConfigVM.selectedKubeConfigID) }
    }
}
