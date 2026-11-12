import Foundation
@testable import Kuma

enum KubectlTestScripts {
    static let noop = "#!/bin/sh\nexit 0\n"

    /// Echoes a single running pod line when `kubectl get` is invoked (pod discovery).
    static func runningPodList(_ podName: String) -> String {
        """
        #!/bin/sh
        if [ "$1" = "get" ]; then
          echo "pod/\(podName)"
        fi
        exit 0
        """
    }
}

struct KubectlTestFixture {
    let kubectlPath: String
    let kubeconfig: URL
    private let cleanupBlock: () -> Void

    var cleanup: () -> Void { cleanupBlock }

    static func install(script: String) throws -> KubectlTestFixture {
        let kubectlKey = KumaSettingsKey.customKubectlPath
        let prior = UserDefaults.standard.string(forKey: kubectlKey)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kuma-kubectl-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fakeKubectl = tempDir.appendingPathComponent("kubectl")
        try script.write(to: fakeKubectl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeKubectl.path)
        UserDefaults.standard.set(fakeKubectl.path, forKey: kubectlKey)

        let kubeconfigURL = tempDir.appendingPathComponent("config")
        try "apiVersion: v1\nkind: Config\n".write(to: kubeconfigURL, atomically: true, encoding: .utf8)

        return KubectlTestFixture(
            kubectlPath: fakeKubectl.path,
            kubeconfig: kubeconfigURL,
            cleanupBlock: {
                try? FileManager.default.removeItem(at: tempDir)
                if let prior {
                    UserDefaults.standard.set(prior, forKey: kubectlKey)
                } else {
                    UserDefaults.standard.removeObject(forKey: kubectlKey)
                }
            }
        )
    }
}
