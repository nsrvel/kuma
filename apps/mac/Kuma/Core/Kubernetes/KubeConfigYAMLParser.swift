import Foundation

/// Line-based kubeconfig YAML helpers shared by UI validation and kubectl execution.
enum KubeConfigYAMLParser {
    nonisolated static func parseCurrentContext(fromYaml yaml: String) -> String? {
        let lines = yaml.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.starts(with: "current-context:") {
                let parts = trimmed.components(separatedBy: ":")
                if parts.count >= 2 {
                    let ctx = parts[1]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "\"", with: "")
                        .replacingOccurrences(of: "'", with: "")
                    return ctx.isEmpty ? nil : ctx
                }
            }
        }
        return nil
    }

    nonisolated static func parseContexts(fromYaml yaml: String) -> [String] {
        var contexts: [String] = []
        var inContextsBlock = false

        for line in yaml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.starts(with: "contexts:") {
                inContextsBlock = true
                continue
            }
            if inContextsBlock {
                if !line.starts(with: " ") && !line.starts(with: "\t") && trimmed.contains(":") && !trimmed.starts(with: "-") {
                    break
                }
                if trimmed.starts(with: "- name:") || (trimmed.starts(with: "name:") && line.starts(with: " ")) {
                    let parts = trimmed.components(separatedBy: "name:")
                    if parts.count >= 2 {
                        let name = parts[1]
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: "\"", with: "")
                            .replacingOccurrences(of: "'", with: "")
                        if !name.isEmpty && !contexts.contains(name) {
                            contexts.append(name)
                        }
                    }
                }
            }
        }
        return contexts
    }

    /// Picks a kubectl `--context` that exists in `yaml`, ignoring stale provider values.
    nonisolated static func resolveContextName(stored: String?, in yaml: String) -> String? {
        let contexts = parseContexts(fromYaml: yaml)
        let storedTrimmed = stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !storedTrimmed.isEmpty && contexts.contains(storedTrimmed) {
            return storedTrimmed
        }
        if let current = parseCurrentContext(fromYaml: yaml), contexts.contains(current) {
            return current
        }
        return contexts.first
    }
}
