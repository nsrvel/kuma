import SwiftUI

/// Restrained execution-state colors — indicator (dot/halo) vs calmer label text.
public enum KumaStatus {
    public static let runningIndicator = Color(nsColor: dynamicSystemGreen)
    public static let transitionalIndicator = Color(nsColor: dynamicTransitionalAmber)
    public static let failedIndicator = Color(nsColor: dynamicSystemRed)
    /// Saturated fill for primary-style Stop / destructive buttons (not status dots).
    public static let destructiveButtonFill = Color(nsColor: dynamicDestructiveButtonFill)
    public static let idleIndicator = Color(nsColor: .tertiaryLabelColor)
    public static let disabledIndicator = Color(nsColor: .secondaryLabelColor).opacity(0.55)

    public static func indicatorColor(for state: ServiceState) -> Color {
        switch state {
        case .stopped:  return idleIndicator
        case .starting, .stopping, .reconnecting: return transitionalIndicator
        case .running:  return runningIndicator
        case .crashed:  return failedIndicator
        }
    }

    public static func indicatorColor(for execution: ServiceExecutionState) -> Color {
        switch execution {
        case .idle:     return idleIndicator
        case .starting, .stopping, .reconnecting: return transitionalIndicator
        case .running:  return runningIndicator
        case .crashed, .failed: return failedIndicator
        }
    }

    public static func labelColor(for state: ServiceState) -> Color {
        switch state {
        case .stopped:  return Color(nsColor: .secondaryLabelColor)
        case .starting, .stopping, .reconnecting: return Color(nsColor: .secondaryLabelColor)
        case .running:  return Color(nsColor: .labelColor)
        case .crashed:  return failedIndicator.opacity(0.92)
        }
    }

    public static func labelColor(for execution: ServiceExecutionState) -> Color {
        labelColor(for: execution.legacyState)
    }

    public static var disabledLabel: Color {
        Color(nsColor: .tertiaryLabelColor)
    }

    // MARK: - Dynamic NSColor (light / dark calibrated)

    private static let dynamicSystemGreen = NSColor(name: nil, dynamicProvider: { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(red: 0.36, green: 0.84, blue: 0.48, alpha: 1.0)
            : NSColor(red: 0.13, green: 0.68, blue: 0.32, alpha: 1.0)
    })

    private static let dynamicTransitionalAmber = NSColor(name: nil, dynamicProvider: { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(red: 0.98, green: 0.72, blue: 0.28, alpha: 1.0)
            : NSColor(red: 0.85, green: 0.55, blue: 0.08, alpha: 1.0)
    })

    private static let dynamicSystemRed = NSColor(name: nil, dynamicProvider: { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(red: 1.0, green: 0.45, blue: 0.42, alpha: 1.0)
            : NSColor.systemRed
    })

    private static let dynamicDestructiveButtonFill = NSColor(name: nil, dynamicProvider: { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(red: 0.90, green: 0.22, blue: 0.20, alpha: 1.0)
            : NSColor(red: 0.78, green: 0.10, blue: 0.12, alpha: 1.0)
    })
}
