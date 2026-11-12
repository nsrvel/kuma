import SwiftUI

/// Leading tone wash + hairline stroke for inspector banners and list rows.
struct KumaToneWashBackground: View {
    let tone: Color
    var washOpacity: Double
    var strokeOpacity: Double
    var baseOpacity: Double = 0.025
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(baseOpacity))
            .overlay {
                if washOpacity > 0 {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tone.opacity(washOpacity), tone.opacity(0)],
                                startPoint: .leading,
                                endPoint: UnitPoint(x: 0.7, y: 0.5)
                            )
                        )
                }
            }
            .overlay {
                if strokeOpacity > 0 {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(tone.opacity(strokeOpacity), lineWidth: 0.8)
                }
            }
    }
}

/// Neutral selected/hover chrome for inspector list rows and segment controls (not accent or status tone).
struct KumaInspectorListRowSelectionChrome: View {
    enum Style {
        /// Provider / kube config rows — keep selection subtle.
        case listRow
        case segmentControl
    }

    let isSelected: Bool
    let isHovered: Bool
    var style: Style = .listRow

    private var selectedFillOpacity: Double {
        switch style {
        case .listRow: 0.048
        case .segmentControl: 0.054
        }
    }

    private var hoverFillOpacity: Double {
        switch style {
        case .listRow: 0.024
        case .segmentControl: 0.03
        }
    }

    private var selectedStrokeOpacity: Double {
        switch style {
        case .listRow: 0.62
        case .segmentControl: 0.7
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                isSelected
                    ? Color.primary.opacity(selectedFillOpacity)
                    : (isHovered ? Color.primary.opacity(hoverFillOpacity) : Color.clear)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            KumaColors.borderSubtle.opacity(selectedStrokeOpacity),
                            lineWidth: style == .listRow ? 0.6 : 0.7
                        )
                }
            }
    }
}
