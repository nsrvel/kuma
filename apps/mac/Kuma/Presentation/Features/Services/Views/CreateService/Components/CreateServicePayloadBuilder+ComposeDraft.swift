import Foundation

extension CreateServicePayloadBuilder {
    static func applyComposeDraft(
        _ draft: ServiceComposeDraft,
        yaml: inout String?,
        composePath: inout String?,
        script: inout String?,
        scriptPath: inout String?
    ) {
        yaml = draft.yamlConfig.isEmpty ? nil : draft.yamlConfig
        let trimmedComposePath = draft.composeFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        composePath = trimmedComposePath.isEmpty ? nil : trimmedComposePath
        script = draft.initialScript.isEmpty ? nil : draft.initialScript
        let trimmedScriptPath = draft.initialScriptPath.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptPath = trimmedScriptPath.isEmpty ? nil : trimmedScriptPath
    }

    static func composeDraftIsValid(_ draft: ServiceComposeDraft) -> Bool {
        !draft.yamlConfig.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draft.composeFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
