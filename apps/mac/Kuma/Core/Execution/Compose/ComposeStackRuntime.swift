import Foundation

enum ComposeStackRuntime {
    static func runningContainerIDs(
        context: ComposeStackContext,
        projectBinding: ComposeProjectBinding
    ) async -> [String] {
        let args = context.composeArguments(
            projectBinding: projectBinding,
            subcommand: ["ps", "-q", "--status", "running"]
        )
        let ps = try? await EphemeralCLI.run(
            executablePath: context.binaryPath,
            arguments: args,
            workingDirectory: context.workingDirectory,
            timeout: 20,
            stdio: .captureSeparated
        )
        guard ps?.terminationStatus == 0 else { return [] }
        return ps?.stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    /// Adopt a Terminal stack when it is already up on the implicit compose project and Kuma's project is empty.
    static func shouldAdoptImplicitDefaultStack(context: ComposeStackContext) async -> Bool {
        let kumaIDs = await runningContainerIDs(context: context, projectBinding: .kumaProject)
        guard kumaIDs.isEmpty else { return false }
        let implicitIDs = await runningContainerIDs(context: context, projectBinding: .implicitDefault)
        return !implicitIDs.isEmpty
    }
}
