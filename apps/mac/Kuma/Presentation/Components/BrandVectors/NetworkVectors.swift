import SwiftUI

/// Universal '>_' Terminal Prompt Vector
public struct ShellPromptVector: View {
    public init() {}

    public var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let scaleX = size.width / 24.0
                let scaleY = size.height / 24.0

                // '>' Prompt
                var chevron = Path()
                chevron.move(to: CGPoint(x: 3.5 * scaleX, y: 5.5 * scaleY))
                chevron.addLine(to: CGPoint(x: 10.5 * scaleX, y: 12.0 * scaleY))
                chevron.addLine(to: CGPoint(x: 3.5 * scaleX, y: 18.5 * scaleY))
                ctx.stroke(chevron, with: .foreground, style: StrokeStyle(lineWidth: max(1.4, size.width * 0.12), lineCap: .round, lineJoin: .round))

                // '_' Underscore cursor
                var cursor = Path()
                cursor.move(to: CGPoint(x: 13.0 * scaleX, y: 18.5 * scaleY))
                cursor.addLine(to: CGPoint(x: 20.5 * scaleX, y: 18.5 * scaleY))
                ctx.stroke(cursor, with: .foreground, style: StrokeStyle(lineWidth: max(1.4, size.width * 0.12), lineCap: .round))
            }
            .drawingGroup()
        }
    }
}

/// Official Cloudflare Cloud Vector
public struct CloudflareBrandVector: View {
    public init() {}

    public var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let scaleX = size.width / 24.0
                let scaleY = size.height / 24.0

                var cloud = Path()
                cloud.move(to: CGPoint(x: 19.5 * scaleX, y: 17.5 * scaleY))
                cloud.addLine(to: CGPoint(x: 4.5 * scaleX, y: 17.5 * scaleY))
                cloud.addCurve(
                    to: CGPoint(x: 4.5 * scaleX, y: 11.5 * scaleY),
                    control1: CGPoint(x: 2.0 * scaleX, y: 17.5 * scaleY),
                    control2: CGPoint(x: 2.0 * scaleX, y: 11.5 * scaleY)
                )
                cloud.addCurve(
                    to: CGPoint(x: 10.5 * scaleX, y: 7.0 * scaleY),
                    control1: CGPoint(x: 4.5 * scaleX, y: 8.5 * scaleY),
                    control2: CGPoint(x: 7.5 * scaleX, y: 6.5 * scaleY)
                )
                cloud.addCurve(
                    to: CGPoint(x: 18.5 * scaleX, y: 10.5 * scaleY),
                    control1: CGPoint(x: 15.0 * scaleX, y: 6.5 * scaleY),
                    control2: CGPoint(x: 18.0 * scaleX, y: 8.5 * scaleY)
                )
                cloud.addCurve(
                    to: CGPoint(x: 19.5 * scaleX, y: 17.5 * scaleY),
                    control1: CGPoint(x: 21.5 * scaleX, y: 11.5 * scaleY),
                    control2: CGPoint(x: 22.0 * scaleX, y: 17.5 * scaleY)
                )
                cloud.closeSubpath()

                ctx.fill(cloud, with: .foreground)
            }
            .drawingGroup()
        }
    }
}

/// Official Ngrok Curved Archway 'n' Vector
public struct NgrokBrandVector: View {
    public init() {}

    public var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let scaleX = size.width / 20.0
                let scaleY = size.height / 20.0

                // Iconic ngrok lower-case 'n' archway geometry
                var nPath = Path()
                // Left vertical stem
                nPath.move(to: CGPoint(x: 4.5 * scaleX, y: 16.5 * scaleY))
                nPath.addLine(to: CGPoint(x: 4.5 * scaleX, y: 4.5 * scaleY))
                // Top rounded shoulder curve
                nPath.addCurve(
                    to: CGPoint(x: 15.5 * scaleX, y: 8.5 * scaleY),
                    control1: CGPoint(x: 4.5 * scaleX, y: 3.5 * scaleY),
                    control2: CGPoint(x: 15.5 * scaleX, y: 3.5 * scaleY)
                )
                // Right vertical stem
                nPath.addLine(to: CGPoint(x: 15.5 * scaleX, y: 16.5 * scaleY))

                ctx.stroke(
                    nPath,
                    with: .foreground,
                    style: StrokeStyle(
                        lineWidth: max(2.0, size.width * 0.19),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
            .drawingGroup()
        }
    }
}
