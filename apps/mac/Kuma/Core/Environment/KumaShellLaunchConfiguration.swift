import Foundation

/// Resolves the user-configured login shell for script providers.
public enum KumaShellLaunchConfiguration {
    private static let fallbackShell = "/bin/zsh"

    public static func validatedShellPath(defaults: UserDefaults = .standard) -> String {
        let configured = defaults.string(forKey: KumaSettingsKey.defaultShell) ?? fallbackShell
        let expanded = NSString(string: configured).expandingTildeInPath
        if FileManager.default.isExecutableFile(atPath: expanded) {
            return expanded
        }
        return fallbackShell
    }

    public static func launchSpec(
        runCommand: String,
        defaults: UserDefaults = .standard
    ) -> (executable: String, arguments: [String]) {
        let shellPath = validatedShellPath(defaults: defaults)
        let shellName = (shellPath as NSString).lastPathComponent.lowercased()

        if shellName == "fish" {
            return (shellPath, ["-c", "eval $argv[1]", "--", runCommand])
        }

        let bootstrap: String
        let teardownTrap = "trap 'kill -TERM 0 2>/dev/null || true' EXIT INT TERM"
        if shellName == "bash" {
            bootstrap = "[ -f ~/.bash_profile ] && source ~/.bash_profile 2>/dev/null; [ -f ~/.bashrc ] && source ~/.bashrc 2>/dev/null; \(teardownTrap); eval \"$1\""
        } else {
            bootstrap = "[ -f ~/.zprofile ] && source ~/.zprofile 2>/dev/null; [ -f ~/.zshrc ] && source ~/.zshrc 2>/dev/null; [ -f ~/.bash_profile ] && source ~/.bash_profile 2>/dev/null; \(teardownTrap); eval \"$1\""
        }

        return (shellPath, ["-c", bootstrap, "--", runCommand])
    }
}
