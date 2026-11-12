import SwiftUI

/// Official Kubernetes 7-Spoke Helm Wheel Vector (Balanced Scale)
public struct KubernetesBrandVector: View {
    public init() {}

    public var body: some View {
        Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) * 0.455
                let innerRadius = radius * 0.44

                // Outer 7-sided polygon / rim
                var rim = Path()
                let spokeCount = 7
                for i in 0..<spokeCount {
                    let angle = (Double(i) * (360.0 / Double(spokeCount)) - 90.0) * .pi / 180.0
                    let pt = CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius)
                    if i == 0 { rim.move(to: pt) } else { rim.addLine(to: pt) }
                }
                rim.closeSubpath()
                ctx.stroke(rim, with: .foreground, style: StrokeStyle(lineWidth: max(1.2, size.width * 0.11), lineJoin: .round))

                // Center hub
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - innerRadius * 0.55, y: center.y - innerRadius * 0.55, width: innerRadius * 1.1, height: innerRadius * 1.1)), with: .foreground)

                // 7 Spokes connecting hub to rim
                for i in 0..<spokeCount {
                    let angle = (Double(i) * (360.0 / Double(spokeCount)) - 90.0) * .pi / 180.0
                    var spoke = Path()
                    spoke.move(to: center)
                    spoke.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius))
                    ctx.stroke(spoke, with: .foreground, style: StrokeStyle(lineWidth: max(1.0, size.width * 0.085)))
                }
        }
    }
}
