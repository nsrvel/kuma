import Foundation

enum KubePortForwardPlan {
    struct Built: Sendable {
        let arguments: [String]
        let localPorts: [Int]
        let kubectlReference: String
    }

    static func build(
        resolved: KubeResolvedTarget,
        exec: KubeExecCredentials,
        portMappings: [ServicePortMapping],
        namespace: String?,
        context: String?
    ) -> Built {
        var args = ["port-forward", resolved.kubectlReference]

        if let kubeconfigPath = exec.kubeconfigPath, !kubeconfigPath.isEmpty {
            args.append("--kubeconfig")
            args.append(kubeconfigPath)
        }

        for mapping in portMappings {
            args.append("\(mapping.localPort):\(mapping.remotePort)")
        }

        if let namespace, !namespace.isEmpty {
            args.append("-n")
            args.append(namespace)
        }

        if let context, !context.isEmpty {
            args.append("--context")
            args.append(context)
        }

        return Built(
            arguments: args,
            localPorts: portMappings.map(\.localPort),
            kubectlReference: resolved.kubectlReference
        )
    }
}
