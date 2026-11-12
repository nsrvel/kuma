import AppKit

// MARK: - NSApplication Extensions

extension NSApplication {
    public static var sharedIfRunning: NSApplication? {
        if NSApp != nil {
            return NSApp
        }
        return nil
    }
}
