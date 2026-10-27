import SwiftUI

/// Compact service status pill for deck cards and table rows.
public struct StatusPillView: View {
    private let text: String
    private let indicatorColor: Color
    private let labelColor: Color
    private let status: ServiceState
    private let showsOrbit: Bool
    private let showsGlow: Bool
    private let deckStyle: Bool

    public init(runtime: ServiceRuntimeState, isDisabled: Bool = false, deckStyle: Bool = false) {
        self.deckStyle = deckStyle
        if isDisabled {
            self.text = "Disabled"
            self.indicatorColor = KumaStatus.disabledIndicator
            self.labelColor = KumaStatus.disabledLabel
            self.status = .stopped
            self.showsOrbit = false
            self.showsGlow = false
        } else {
            self.text = runtime.statusTitle
            self.indicatorColor = runtime.status.color
            self.labelColor = runtime.status.labelColor
            self.status = runtime.status
            let transitional = runtime.isLoading
                || runtime.status == .starting
                || runtime.status == .stopping
                || runtime.status == .reconnecting
            self.showsOrbit = transitional
            self.showsGlow = runtime.status == .running && !transitional
        }
    }

    public var body: some View {
        HStack(spacing: 5) {
            StatusPillLeadingIndicator(
                color: indicatorColor,
                showsOrbit: showsOrbit,
                showsGlow: showsGlow,
                deckStyle: deckStyle
            )
            .frame(width: 12, height: 12)

            Text(text)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .contentTransition(.interpolate)
        }
        .fixedSize()
        .animation(statusPillAnimation, value: animationKey)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(text) service")
    }

    private var animationKey: String {
        "\(text)-\(showsOrbit)-\(showsGlow)-\(status.rawValue)"
    }

    private var statusPillAnimation: Animation? {
        deckStyle ? .easeOut(duration: 0.18) : .smooth(duration: 0.28)
    }
}

private enum StatusPillDeckTiming {
    static let orbitPeriod: TimeInterval = 1.05
    /// ponytail: ~12fps tick — same spin read as repeatForever, less display-link pressure in large grids
    static let orbitTick: TimeInterval = 1.0 / 12.0
}

// MARK: - Leading indicator (fixed footprint — avoids layout flicker on state change)

struct StatusPillLeadingIndicator: View {
    let color: Color
    let showsOrbit: Bool
    let showsGlow: Bool
    var deckStyle: Bool = false

    var body: some View {
        ZStack {
            if showsGlow {
                Circle()
                    .fill(color.opacity(0.38))
                    .frame(width: 8, height: 8)
                    .transition(.opacity)
            }

            if showsOrbit {
                if deckStyle {
                    StatusPillDeckOrbitRing(color: color)
                } else {
                    StatusPillOrbitRing(color: color)
                }
            }

            Circle()
                .fill(color)
                .frame(width: 4, height: 4)
        }
        .animation(deckStyle ? .easeOut(duration: 0.18) : .smooth(duration: 0.28), value: showsOrbit)
        .animation(deckStyle ? .easeOut(duration: 0.18) : .smooth(duration: 0.28), value: showsGlow)
    }
}

/// Deck grid: stepped rotation via TimelineView (visual match, lighter than `repeatForever`).
private struct StatusPillDeckOrbitRing: View {
    let color: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: StatusPillDeckTiming.orbitTick)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: StatusPillDeckTiming.orbitPeriod)
            let degrees = (phase / StatusPillDeckTiming.orbitPeriod) * 360
            Circle()
                .trim(from: 0.06, to: 0.42)
                .stroke(
                    color.opacity(0.85),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                )
                .frame(width: 9, height: 9)
                .rotationEffect(.degrees(degrees))
        }
    }
}

/// Thin orbit stroke — inspector / table (animated).
private struct StatusPillOrbitRing: View {
    let color: Color
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .trim(from: 0.06, to: 0.42)
            .stroke(
                color.opacity(0.85),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
            )
            .frame(width: 9, height: 9)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(
                .linear(duration: 1.05).repeatForever(autoreverses: false),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
            .onDisappear { isAnimating = false }
    }
}

/// Pure SwiftUI spinner — inspector / kube rows (not deck status pills).
public struct KumaActivityIndicator: View {
    public var size: CGFloat
    public var color: Color
    public var lineWidth: CGFloat

    @State private var isAnimating: Bool = false

    public init(
        size: CGFloat = 12,
        color: Color = .secondary,
        lineWidth: CGFloat = 1.75
    ) {
        self.size = size
        self.color = color
        self.lineWidth = lineWidth
    }

    public var body: some View {
        Circle()
            .trim(from: 0.0, to: 0.72)
            .stroke(
                color,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
            .animation(
                .linear(duration: 0.85).repeatForever(autoreverses: false),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
            .onDisappear {
                isAnimating = false
            }
    }
}

#Preview("Status pills") {
    VStack(alignment: .leading, spacing: 10) {
        StatusPillView(runtime: .init(status: .stopped))
        StatusPillView(runtime: .init(status: .starting, isLoading: true))
        StatusPillView(runtime: .init(status: .running))
        StatusPillView(runtime: .init(status: .stopping, isLoading: true))
        StatusPillView(runtime: .init(status: .crashed))
        StatusPillView(runtime: .init(), isDisabled: true)
        StatusPillView(runtime: .init(status: .starting, isLoading: true), deckStyle: true)
        StatusPillView(runtime: .init(status: .running), deckStyle: true)
    }
    .padding()
}
