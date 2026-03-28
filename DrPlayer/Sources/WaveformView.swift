import SwiftUI

struct WaveformView: View {
    let peaks: [Float]
    let progress: Double
    let playedColor: Color
    let unplayedColor: Color

    var body: some View {
        Canvas { context, size in
            let barCount = peaks.count
            guard barCount > 0 else { return }

            let spacing: CGFloat = 1
            let barWidth = (size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount)
            let clampedWidth = max(1, barWidth)
            let progressX = size.width * progress
            let midY = size.height / 2

            for i in 0..<barCount {
                let x = CGFloat(i) * (clampedWidth + spacing)
                let peakHeight = max(2, CGFloat(peaks[i]) * size.height)
                let rect = CGRect(
                    x: x,
                    y: midY - peakHeight / 2,
                    width: clampedWidth,
                    height: peakHeight
                )
                let color = x < progressX ? playedColor : unplayedColor
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
            }
        }
    }
}
