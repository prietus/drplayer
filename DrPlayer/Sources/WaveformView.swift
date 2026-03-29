import SwiftUI

struct WaveformView: View {
    let peaks: [Float]
    let progress: Double
    let playedColor: Color
    let unplayedColor: Color

    var body: some View {
        Canvas { context, size in
            let count = peaks.count
            guard count > 1 else { return }

            let midY = size.height / 2
            let progressX = size.width * progress

            // Build smooth waveform path (top half)
            let topPath = smoothWaveformPath(peaks: peaks, size: size, midY: midY, mirror: false)
            // Build smooth waveform path (bottom half, mirrored)
            let bottomPath = smoothWaveformPath(peaks: peaks, size: size, midY: midY, mirror: true)

            // Combine into a single closed shape
            var fullShape = topPath
            fullShape.addPath(bottomPath)

            // Clip to played region and draw
            let playedRect = CGRect(x: 0, y: 0, width: progressX, height: size.height)
            let unplayedRect = CGRect(x: progressX, y: 0, width: size.width - progressX, height: size.height)

            // Draw played portion
            context.drawLayer { ctx in
                ctx.clip(to: Path(playedRect))
                ctx.fill(fullShape, with: .color(playedColor))
            }

            // Draw unplayed portion
            context.drawLayer { ctx in
                ctx.clip(to: Path(unplayedRect))
                ctx.fill(fullShape, with: .color(unplayedColor))
            }
        }
    }

    /// Build a smooth path through the peaks using Catmull-Rom → cubic Bezier conversion
    private func smoothWaveformPath(peaks: [Float], size: CGSize, midY: CGFloat, mirror: Bool) -> Path {
        let count = peaks.count
        let step = size.width / CGFloat(count - 1)
        let sign: CGFloat = mirror ? 1 : -1

        // Generate points
        var points: [CGPoint] = []
        for i in 0..<count {
            let x = CGFloat(i) * step
            let amplitude = max(1, CGFloat(peaks[i]) * midY * 0.95)
            let y = midY + sign * amplitude
            points.append(CGPoint(x: x, y: y))
        }

        var path = Path()
        path.move(to: CGPoint(x: 0, y: midY))
        path.addLine(to: points[0])

        // Catmull-Rom spline through points
        for i in 0..<points.count {
            let p0 = points[max(0, i - 1)]
            let p1 = points[i]
            let p2 = points[min(points.count - 1, i + 1)]
            let p3 = points[min(points.count - 1, i + 2)]

            // Convert Catmull-Rom to cubic Bezier control points
            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )

            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }

        path.addLine(to: CGPoint(x: size.width, y: midY))
        path.addLine(to: CGPoint(x: 0, y: midY))
        path.closeSubpath()

        return path
    }
}
