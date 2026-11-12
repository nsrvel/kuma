import AppKit

// MARK: - KumaHapticManager

/// Centralized manager for native macOS Force Touch trackpad haptics (Taptic Engine).
/// Provides subtle physical feedback for digital actions without blocking or impacting non-trackpad users.
@MainActor
public final class KumaHapticManager {
    public static let shared = KumaHapticManager()

    public var performer: (any NSHapticFeedbackPerformer)?

    public init(performer: (any NSHapticFeedbackPerformer)? = NSHapticFeedbackManager.defaultPerformer) {
        self.performer = performer
    }

    /// Triggers a standard subtle tactile tap (e.g. switch toggled, star toggled).
    public func tap() {
        performer?.perform(.generic, performanceTime: .default)
    }

    /// Triggers an alignment notch (e.g. drag-and-drop reorder target).
    public func alignment() {
        performer?.perform(.alignment, performanceTime: .default)
    }

    /// Triggers a level change cue (e.g. switching active workspace).
    public func levelChange() {
        performer?.perform(.levelChange, performanceTime: .default)
    }
}
