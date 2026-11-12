import AppKit
import Foundation
import os

public enum SingleInstanceGuard {
    private static let logger = Logger(subsystem: "lokastudio.kuma", category: "SingleInstanceGuard")

    /// Checks if another instance of Kuma is already running.
    /// If an existing instance is found, it brings that instance to front and returns `true`.
    @discardableResult
    @MainActor
    public static func activateExistingInstanceIfRunning() -> Bool {
        // Skip check during XCTest / Swift Testing or when attached to a debugger (e.g. Xcode LLDB)
        if isDebuggerAttached ||
           ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
           ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil ||
           ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil ||
           NSClassFromString("XCTestCase") != nil ||
           Bundle.allBundles.contains(where: { $0.bundlePath.hasSuffix(".xctest") }) {
            return false
        }

        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        let currentPID = ProcessInfo.processInfo.processIdentifier

        if let existingApp = runningApps.first(where: { $0.processIdentifier != currentPID }) {
            logger.info("Found running Kuma instance (PID: \(existingApp.processIdentifier)). Bringing to front.")
            existingApp.activate()
            return true
        }

        return false
    }

    /// Indicates whether the application is running in an automated test environment.
    public static var isTestingEnvironment: Bool {
        ProcessInfo.processInfo.environment["KUMA_UNIT_TESTS"] != nil ||
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil ||
        ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil ||
        NSClassFromString("XCTestCase") != nil ||
        Bundle.allBundles.contains(where: { $0.bundlePath.hasSuffix(".xctest") })
    }

    /// Determines if the current process is running under a debugger (such as LLDB in Xcode).
    public static var isDebuggerAttached: Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let junk = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard junk == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }
}
