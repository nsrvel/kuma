import Foundation

enum KubeTargetNamingHints {
    /// Deployment-style pod name without ReplicaSet + pod suffix (e.g. `padiumkm-ms-masterdata-6cf68f49b4-qgdg7` → `padiumkm-ms-masterdata`).
    nonisolated static func replicaPodWorkloadStem(podName: String) -> String? {
        let parts = podName.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3 else { return nil }
        let podHash = parts[parts.count - 1]
        let rsHash = parts[parts.count - 2]
        guard podHash.count == 5,
              (8 ... 10).contains(rsHash.count),
              podHash.allSatisfy({ $0.isLetter || $0.isNumber }),
              rsHash.allSatisfy({ $0.isLetter || $0.isNumber })
        else { return nil }
        return parts.dropLast(2).joined(separator: "-")
    }

    /// Heuristic: deployment/service-style name, not a concrete `…-<rs>-<pod>` instance.
    static func looksLikeStableWorkloadName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard !trimmed.isEmpty else { return false }
        if trimmed.lowercased() == "pod" { return false }
        return replicaPodWorkloadStem(podName: trimmed) == nil
    }
}
