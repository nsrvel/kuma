import UniformTypeIdentifiers

public enum KumaScriptFileSupport {
    public static let allowedTypes: [UTType] = {
        var types: [UTType] = []
        if let sh = UTType(filenameExtension: "sh") { types.append(sh) }
        if let bash = UTType(filenameExtension: "bash") { types.append(bash) }
        types.append(.shellScript)
        types.append(.plainText)
        return types
    }()
}
