import SwiftUI

/// Official Docker Brand Vector (1:1 with Official Moby Whale & 9-Box Container Grid, Prominent Scale)
public struct DockerBrandVector: View {
    public init() {}

    public var body: some View {
        Canvas { ctx, size in
                // Scale normalized to 24x24 viewBox with 1.15x prominent scale centered
                let baseScale = min(size.width, size.height) / 24.0 * 1.16
                let offsetX = (size.width - 24.0 * baseScale) / 2.0
                let offsetY = (size.height - 24.0 * baseScale) / 2.0 + (0.5 * baseScale)

                let scaleX = baseScale
                let scaleY = baseScale

                // Container dimensions (exact official Docker 9-container stack)
                let cW = 2.12 * scaleX
                let cH = 1.89 * scaleY
                let cr = 0.22 * scaleX

                // 9 Container Boxes:
                // Row 1 (top): 1 box
                ctx.fill(
                    Path(roundedRect: CGRect(x: offsetX + 11.03 * scaleX, y: offsetY + 3.39 * scaleY, width: cW, height: cH), cornerRadius: cr),
                    with: .foreground
                )

                // Row 2 (middle): 3 boxes
                let row2X: [CGFloat] = [5.14, 8.10, 11.03]
                for x in row2X {
                    ctx.fill(
                        Path(roundedRect: CGRect(x: offsetX + x * scaleX, y: offsetY + 6.10 * scaleY, width: cW, height: cH), cornerRadius: cr),
                        with: .foreground
                    )
                }

                // Row 3 (bottom): 5 boxes
                let row3X: [CGFloat] = [2.22, 5.14, 8.10, 11.03, 13.98]
                for x in row3X {
                    ctx.fill(
                        Path(roundedRect: CGRect(x: offsetX + x * scaleX, y: offsetY + 8.82 * scaleY, width: cW, height: cH), cornerRadius: cr),
                        with: .foreground
                    )
                }

                // Official Moby Whale Body Silhouette
                var whale = Path()
                // Start at top of tail fluke
                whale.move(to: CGPoint(x: offsetX + 23.76 * scaleX, y: offsetY + 9.89 * scaleY))
                // Tail fluke curves
                whale.addCurve(
                    to: CGPoint(x: offsetX + 21.81 * scaleX, y: offsetY + 9.38 * scaleY),
                    control1: CGPoint(x: offsetX + 23.70 * scaleX, y: offsetY + 9.84 * scaleY),
                    control2: CGPoint(x: offsetX + 23.09 * scaleX, y: offsetY + 9.38 * scaleY)
                )
                whale.addCurve(
                    to: CGPoint(x: offsetX + 20.80 * scaleX, y: offsetY + 9.47 * scaleY),
                    control1: CGPoint(x: offsetX + 21.47 * scaleX, y: offsetY + 9.38 * scaleY),
                    control2: CGPoint(x: offsetX + 21.13 * scaleX, y: offsetY + 9.41 * scaleY)
                )
                // Upper tail fin / water spray cutout
                whale.addCurve(
                    to: CGPoint(x: offsetX + 19.08 * scaleX, y: offsetY + 6.90 * scaleY),
                    control1: CGPoint(x: offsetX + 20.55 * scaleX, y: offsetY + 7.77 * scaleY),
                    control2: CGPoint(x: offsetX + 19.15 * scaleX, y: offsetY + 6.94 * scaleY)
                )
                whale.addLine(to: CGPoint(x: offsetX + 18.74 * scaleX, y: offsetY + 6.70 * scaleY))
                whale.addLine(to: CGPoint(x: offsetX + 18.51 * scaleX, y: offsetY + 7.03 * scaleY))
                whale.addCurve(
                    to: CGPoint(x: offsetX + 17.90 * scaleX, y: offsetY + 8.46 * scaleY),
                    control1: CGPoint(x: offsetX + 18.23 * scaleX, y: offsetY + 7.47 * scaleY),
                    control2: CGPoint(x: offsetX + 18.02 * scaleX, y: offsetY + 7.95 * scaleY)
                )
                whale.addCurve(
                    to: CGPoint(x: offsetX + 18.30 * scaleX, y: offsetY + 11.12 * scaleY),
                    control1: CGPoint(x: offsetX + 17.67 * scaleX, y: offsetY + 9.43 * scaleY),
                    control2: CGPoint(x: offsetX + 17.81 * scaleX, y: offsetY + 10.34 * scaleY)
                )
                // Back shelf under containers sloping into forehead
                whale.addCurve(
                    to: CGPoint(x: offsetX + 16.56 * scaleX, y: offsetY + 11.54 * scaleY),
                    control1: CGPoint(x: offsetX + 17.71 * scaleX, y: offsetY + 11.45 * scaleY),
                    control2: CGPoint(x: offsetX + 16.75 * scaleX, y: offsetY + 11.53 * scaleY)
                )
                whale.addLine(to: CGPoint(x: offsetX + 1.65 * scaleX, y: offsetY + 11.54 * scaleY))
                // Forehead to rounded snout tip (smooth aerodynamic sweep, not flat/boxy)
                whale.addCurve(
                    to: CGPoint(x: offsetX + 0.15 * scaleX, y: offsetY + 12.85 * scaleY),
                    control1: CGPoint(x: offsetX + 0.95 * scaleX, y: offsetY + 11.54 * scaleY),
                    control2: CGPoint(x: offsetX + 0.35 * scaleX, y: offsetY + 12.05 * scaleY)
                )
                // Front snout round contour down to jaw
                whale.addCurve(
                    to: CGPoint(x: offsetX + 0.65 * scaleX, y: offsetY + 15.65 * scaleY),
                    control1: CGPoint(x: offsetX + -0.05 * scaleX, y: offsetY + 13.65 * scaleY),
                    control2: CGPoint(x: offsetX + 0.15 * scaleX, y: offsetY + 14.85 * scaleY)
                )
                // Jaw sloping smoothly into chin and underbelly
                whale.addCurve(
                    to: CGPoint(x: offsetX + 3.10 * scaleX, y: offsetY + 19.47 * scaleY),
                    control1: CGPoint(x: offsetX + 1.15 * scaleX, y: offsetY + 17.20 * scaleY),
                    control2: CGPoint(x: offsetX + 1.95 * scaleX, y: offsetY + 18.60 * scaleY)
                )
                // Underbelly swoop
                whale.addCurve(
                    to: CGPoint(x: offsetX + 8.38 * scaleX, y: offsetY + 20.61 * scaleY),
                    control1: CGPoint(x: offsetX + 4.28 * scaleX, y: offsetY + 20.19 * scaleY),
                    control2: CGPoint(x: offsetX + 6.20 * scaleX, y: offsetY + 20.61 * scaleY)
                )
                // Belly upward to tail base
                whale.addCurve(
                    to: CGPoint(x: offsetX + 15.13 * scaleX, y: offsetY + 18.95 * scaleY),
                    control1: CGPoint(x: offsetX + 10.74 * scaleX, y: offsetY + 20.61 * scaleY),
                    control2: CGPoint(x: offsetX + 13.12 * scaleX, y: offsetY + 19.95 * scaleY)
                )
                whale.addCurve(
                    to: CGPoint(x: offsetX + 17.74 * scaleX, y: offsetY + 16.81 * scaleY),
                    control1: CGPoint(x: offsetX + 16.11 * scaleX, y: offsetY + 18.38 * scaleY),
                    control2: CGPoint(x: offsetX + 16.99 * scaleX, y: offsetY + 17.66 * scaleY)
                )
                whale.addCurve(
                    to: CGPoint(x: offsetX + 20.30 * scaleX, y: offsetY + 12.41 * scaleY),
                    control1: CGPoint(x: offsetX + 18.99 * scaleX, y: offsetY + 15.39 * scaleY),
                    control2: CGPoint(x: offsetX + 19.74 * scaleX, y: offsetY + 13.81 * scaleY)
                )
                whale.addLine(to: CGPoint(x: offsetX + 20.52 * scaleX, y: offsetY + 12.41 * scaleY))
                // Lower tail fluke curve
                whale.addCurve(
                    to: CGPoint(x: offsetX + 23.20 * scaleX, y: offsetY + 11.40 * scaleY),
                    control1: CGPoint(x: offsetX + 21.89 * scaleX, y: offsetY + 12.41 * scaleY),
                    control2: CGPoint(x: offsetX + 22.74 * scaleX, y: offsetY + 11.86 * scaleY)
                )
                whale.addCurve(
                    to: CGPoint(x: offsetX + 23.91 * scaleX, y: offsetY + 10.35 * scaleY),
                    control1: CGPoint(x: offsetX + 23.51 * scaleX, y: offsetY + 11.11 * scaleY),
                    control2: CGPoint(x: offsetX + 23.75 * scaleX, y: offsetY + 10.75 * scaleY)
                )
                whale.addLine(to: CGPoint(x: offsetX + 23.76 * scaleX, y: offsetY + 9.89 * scaleY))
                whale.closeSubpath()

                ctx.fill(whale, with: .foreground)

                // Eye (Whale eye dot positioned accurately)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: offsetX + 3.45 * scaleX, y: offsetY + 13.85 * scaleY, width: 0.95 * scaleX, height: 0.95 * scaleY)),
                    with: .color(.black.opacity(0.4))
                )
        }
    }
}
