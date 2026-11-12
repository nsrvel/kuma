import SwiftUI

extension ServiceState {
    /// Chroma for dots, halos, and inspector accents.
    public var color: Color {
        KumaStatus.indicatorColor(for: self)
    }

    public var labelColor: Color {
        KumaStatus.labelColor(for: self)
    }

    public var icon: String {
        switch self {
        case .stopped:  return "stop.fill"
        case .starting: return "play.circle.fill"
        case .running:  return "checkmark.circle.fill"
        case .stopping: return "pause.circle.fill"
        case .reconnecting: return "arrow.triangle.2.circlepath"
        case .crashed:  return "exclamationmark.triangle.fill"
        }
    }
}

extension ServiceExecutionState {
    public var color: Color {
        KumaStatus.indicatorColor(for: self)
    }

    public var labelColor: Color {
        KumaStatus.labelColor(for: self)
    }

    public var icon: String {
        switch self {
        case .idle:     return "stop.fill"
        case .starting: return "play.circle.fill"
        case .running:  return "checkmark.circle.fill"
        case .stopping: return "pause.circle.fill"
        case .reconnecting: return "arrow.triangle.2.circlepath"
        case .crashed:  return "exclamationmark.triangle.fill"
        case .failed:   return "xmark.octagon.fill"
        }
    }
}

extension DeckViewMode {
    public var icon: String {
        switch self {
        case .card:  return "square.grid.2x2"
        case .table: return "list.bullet"
        }
    }
}
