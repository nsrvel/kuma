import Foundation

enum KubeTargetNameMatcher {
    /// Picks the first match from **lexicographically sorted** `names` (caller should sort).
    /// - Wildcard (`*`): substring match on the pattern with stars removed.
    /// - Otherwise: exact name, or (pods only) a running pod named `<pattern>-<replica-suffix>`.
    nonisolated static func firstMatch(
        pattern: String,
        in names: [String],
        allowPodReplicaPrefix: Bool = false
    ) -> String? {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPattern.isEmpty else { return nil }

        let sorted = names.sorted()
        if trimmedPattern.contains("*") {
            let cleanedPattern = trimmedPattern.replacingOccurrences(of: "*", with: "")
            guard !cleanedPattern.isEmpty else { return sorted.first }
            return sorted.first { name in
                name.localizedCaseInsensitiveContains(cleanedPattern)
            }
        }

        if let exact = sorted.first(where: { $0 == trimmedPattern }) {
            return exact
        }

        guard allowPodReplicaPrefix else { return nil }

        let workloadPattern = trimmedPattern.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard !workloadPattern.isEmpty else { return nil }

        let hyphenatedPrefix = workloadPattern + "-"
        if let direct = sorted.first(where: { $0.hasPrefix(hyphenatedPrefix) }) {
            return direct
        }

        // Partial deployment name (e.g. `padiumkm-ms-master` → pod `padiumkm-ms-masterdata-<rs>-<id>`).
        let stemMatches = sorted.filter { podName in
            guard let stem = KubeTargetNamingHints.replicaPodWorkloadStem(podName: podName) else { return false }
            if stem == workloadPattern { return true }
            return stem.hasPrefix(workloadPattern) && stem.count > workloadPattern.count
        }
        guard !stemMatches.isEmpty else { return nil }
        let stems = Set(stemMatches.compactMap { KubeTargetNamingHints.replicaPodWorkloadStem(podName: $0) })
        guard stems.count == 1 else { return nil }
        return stemMatches[0]
    }
}
