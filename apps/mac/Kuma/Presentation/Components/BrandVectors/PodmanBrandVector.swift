import SwiftUI

/// Official Podman Seal Mascot Vector (Refined Authentic Selkie Seal Mascot - Sleek & Centered)
public struct PodmanBrandVector: View {
    public init() {}

    public var body: some View {
        Canvas { ctx, size in
                let baseScale = min(size.width, size.height) / 24.0
                let offsetX = (size.width - 24.0 * baseScale) / 2.0
                let offsetY = (size.height - 24.0 * baseScale) / 2.0

                let scaleX = baseScale
                let scaleY = baseScale

                // Solid seal head silhouette (flatter head crown, sleek tapered snout & neck)
                var head = Path()
                // Top flattened crown
                head.move(to: CGPoint(x: offsetX + 12.0 * scaleX, y: offsetY + 3.0 * scaleY))
                // Right forehead & temple
                head.addCurve(
                    to: CGPoint(x: offsetX + 20.8 * scaleX, y: offsetY + 11.5 * scaleY),
                    control1: CGPoint(x: offsetX + 17.5 * scaleX, y: offsetY + 3.0 * scaleY),
                    control2: CGPoint(x: offsetX + 20.8 * scaleX, y: offsetY + 6.8 * scaleY)
                )
                // Right cheek to tapered neck
                head.addCurve(
                    to: CGPoint(x: offsetX + 17.2 * scaleX, y: offsetY + 21.0 * scaleY),
                    control1: CGPoint(x: offsetX + 20.8 * scaleX, y: offsetY + 16.0 * scaleY),
                    control2: CGPoint(x: offsetX + 19.0 * scaleX, y: offsetY + 19.5 * scaleY)
                )
                // Bottom chin / neck curve
                head.addCurve(
                    to: CGPoint(x: offsetX + 6.8 * scaleX, y: offsetY + 21.0 * scaleY),
                    control1: CGPoint(x: offsetX + 14.5 * scaleX, y: offsetY + 22.0 * scaleY),
                    control2: CGPoint(x: offsetX + 9.5 * scaleX, y: offsetY + 22.0 * scaleY)
                )
                // Left tapered neck to cheek
                head.addCurve(
                    to: CGPoint(x: offsetX + 3.2 * scaleX, y: offsetY + 11.5 * scaleY),
                    control1: CGPoint(x: offsetX + 5.0 * scaleX, y: offsetY + 19.5 * scaleY),
                    control2: CGPoint(x: offsetX + 3.2 * scaleX, y: offsetY + 16.0 * scaleY)
                )
                // Left temple to top crown
                head.addCurve(
                    to: CGPoint(x: offsetX + 12.0 * scaleX, y: offsetY + 3.0 * scaleY),
                    control1: CGPoint(x: offsetX + 3.2 * scaleX, y: offsetY + 6.8 * scaleY),
                    control2: CGPoint(x: offsetX + 6.5 * scaleX, y: offsetY + 3.0 * scaleY)
                )
                head.closeSubpath()

                // Draw filled seal head
                ctx.fill(head, with: .foreground)

                // Eyes (Subtle almond/oval shape)
                let eyeW = 2.0 * scaleX
                let eyeH = 2.4 * scaleY
                ctx.fill(
                    Path(ellipseIn: CGRect(x: offsetX + 7.0 * scaleX, y: offsetY + 8.5 * scaleY, width: eyeW, height: eyeH)),
                    with: .color(.black.opacity(0.55))
                )
                ctx.fill(
                    Path(ellipseIn: CGRect(x: offsetX + 15.0 * scaleX, y: offsetY + 8.5 * scaleY, width: eyeW, height: eyeH)),
                    with: .color(.black.opacity(0.55))
                )

                // Snout / Nose (Triangular rounded seal nose)
                let noseW = 3.6 * scaleX
                let noseH = 2.4 * scaleY
                ctx.fill(
                    Path(ellipseIn: CGRect(x: offsetX + 10.2 * scaleX, y: offsetY + 12.2 * scaleY, width: noseW, height: noseH)),
                    with: .color(.black.opacity(0.6))
                )

                // Whiskers (3 left, 3 right spreading naturally)
                var whiskers = Path()
                // Left whiskers
                whiskers.move(to: CGPoint(x: offsetX + 9.5 * scaleX, y: offsetY + 13.5 * scaleY))
                whiskers.addLine(to: CGPoint(x: offsetX + 4.8 * scaleX, y: offsetY + 12.2 * scaleY))

                whiskers.move(to: CGPoint(x: offsetX + 9.5 * scaleX, y: offsetY + 14.5 * scaleY))
                whiskers.addLine(to: CGPoint(x: offsetX + 4.2 * scaleX, y: offsetY + 15.0 * scaleY))

                whiskers.move(to: CGPoint(x: offsetX + 9.5 * scaleX, y: offsetY + 15.5 * scaleY))
                whiskers.addLine(to: CGPoint(x: offsetX + 5.2 * scaleX, y: offsetY + 17.5 * scaleY))

                // Right whiskers
                whiskers.move(to: CGPoint(x: offsetX + 14.5 * scaleX, y: offsetY + 13.5 * scaleY))
                whiskers.addLine(to: CGPoint(x: offsetX + 19.2 * scaleX, y: offsetY + 12.2 * scaleY))

                whiskers.move(to: CGPoint(x: offsetX + 14.5 * scaleX, y: offsetY + 14.5 * scaleY))
                whiskers.addLine(to: CGPoint(x: offsetX + 19.8 * scaleX, y: offsetY + 15.0 * scaleY))

                whiskers.move(to: CGPoint(x: offsetX + 14.5 * scaleX, y: offsetY + 15.5 * scaleY))
                whiskers.addLine(to: CGPoint(x: offsetX + 18.8 * scaleX, y: offsetY + 17.5 * scaleY))

                ctx.stroke(
                    whiskers,
                    with: .color(.black.opacity(0.45)),
                    style: StrokeStyle(lineWidth: max(0.9, size.width * 0.05), lineCap: .round)
                )
        }
    }
}
