import Foundation

extension Provider {
    /// Ensures kubernetes target fields are persisted (legacy rows may have nils).
    public func withKubernetesDefaults() -> Provider {
        guard type == .kubernetes else { return self }
        var copy = self
        if copy.kubeTargetType == nil || copy.kubeTargetType?.isEmpty == true {
            copy.kubeTargetType = KubeTargetType.pod.rawValue
        }
        if copy.usePattern == nil {
            copy.usePattern = true
        }
        return copy
    }
}
