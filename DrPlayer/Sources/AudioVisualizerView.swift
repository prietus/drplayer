import SwiftUI
import Accelerate

/// Reads PCM audio from MPD's FIFO output and provides samples for visualization.
final class FIFOReader: @unchecked Sendable {
    static let shared = FIFOReader()

    private let sampleRate = 44100
    private let channels = 2
    private let bytesPerSample = 2 // 16-bit
    private let bufferSize = 2048  // samples per channel per read

    private var fileDescriptor: Int32 = -1
    private var readThread: Thread?
    private var running = false

    /// Latest audio samples (mono-mixed, normalized -1..1), updated ~20x/sec
    var samples: [Float] = []
    /// Accumulated samples for FFT (ring buffer, always keeps last fftSize samples)
    private var accumulatedSamples: [Float] = []
    private let fftSize = 2048
    private let lock = NSLock()

    private init() {}

    /// Returns accumulated samples for FFT analysis (larger buffer than single read)
    func getAccumulatedSamples() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return accumulatedSamples
    }

    func start() {
        guard !running else { return }

        // Ensure FIFO output is configured
        AppSettings.ensureFifoOutput()

        running = true
        readThread = Thread { [weak self] in
            self?.readLoop()
        }
        readThread?.qualityOfService = .userInteractive
        readThread?.start()
    }

    func stop() {
        running = false
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    func getSamples() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    private func readLoop() {
        let path = AppSettings.fifoPath
        let frameSize = channels * bytesPerSample
        let readBytes = bufferSize * frameSize
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: readBytes)
        defer { buffer.deallocate() }

        while running {
            // Open FIFO (blocks until MPD writes)
            if fileDescriptor < 0 {
                fileDescriptor = open(path, O_RDONLY)
                if fileDescriptor < 0 {
                    Thread.sleep(forTimeInterval: 0.5)
                    continue
                }
            }

            let bytesRead = read(fileDescriptor, buffer, readBytes)
            if bytesRead <= 0 {
                // FIFO closed (MPD stopped), reopen
                close(fileDescriptor)
                fileDescriptor = -1
                lock.lock()
                samples = []
                accumulatedSamples = []
                lock.unlock()
                Thread.sleep(forTimeInterval: 0.1)
                continue
            }

            // Convert 16-bit signed stereo PCM to mono float
            let sampleCount = bytesRead / frameSize
            var mono = [Float](repeating: 0, count: sampleCount)

            for i in 0..<sampleCount {
                let offset = i * frameSize
                let left = Int16(buffer[offset]) | (Int16(buffer[offset + 1]) << 8)
                let right = Int16(buffer[offset + 2]) | (Int16(buffer[offset + 3]) << 8)
                mono[i] = (Float(left) + Float(right)) / (2.0 * 32768.0)
            }

            lock.lock()
            samples = mono
            // Accumulate for FFT: append new samples, keep last fftSize
            accumulatedSamples.append(contentsOf: mono)
            if accumulatedSamples.count > fftSize {
                accumulatedSamples.removeFirst(accumulatedSamples.count - fftSize)
            }
            lock.unlock()
        }

        close(fileDescriptor)
        fileDescriptor = -1
    }
}

// MARK: - Oscilloscope View

/// Real-time oscilloscope that renders audio waveform from MPD's FIFO output.
struct OscilloscopeView: View {
    @State private var samples: [Float] = []
    @State private var timer: Timer?

    let lineColor: Color
    let backgroundColor: Color

    init(lineColor: Color = .green, backgroundColor: Color = .black) {
        self.lineColor = lineColor
        self.backgroundColor = backgroundColor
    }

    var body: some View {
        Canvas { context, size in
            // Background
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(backgroundColor))

            guard !samples.isEmpty else {
                // Draw flat line when no data
                let midY = size.height / 2
                var flat = Path()
                flat.move(to: CGPoint(x: 0, y: midY))
                flat.addLine(to: CGPoint(x: size.width, y: midY))
                context.stroke(flat, with: .color(lineColor.opacity(0.3)), lineWidth: 1)
                return
            }

            let midY = size.height / 2
            let count = samples.count
            let step = size.width / CGFloat(count - 1)

            // Build smooth path through samples
            var path = Path()
            path.move(to: CGPoint(x: 0, y: midY + CGFloat(samples[0]) * midY * 0.9))

            // Use every Nth sample for smoother rendering
            let stride = max(1, count / Int(size.width))
            var points: [CGPoint] = []
            for i in Swift.stride(from: 0, to: count, by: stride) {
                let x = CGFloat(i) * step
                let y = midY + CGFloat(samples[i]) * midY * 0.9
                points.append(CGPoint(x: x, y: y))
            }

            guard points.count > 2 else { return }

            path.move(to: points[0])
            for i in 0..<points.count - 1 {
                let p0 = points[max(0, i - 1)]
                let p1 = points[i]
                let p2 = points[min(points.count - 1, i + 1)]
                let p3 = points[min(points.count - 1, i + 2)]

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

            // Glow effect: draw thicker translucent line behind
            context.stroke(path, with: .color(lineColor.opacity(0.3)), lineWidth: 4)
            context.stroke(path, with: .color(lineColor.opacity(0.6)), lineWidth: 2)
            context.stroke(path, with: .color(lineColor), lineWidth: 1)

            // Center line (subtle)
            var centerLine = Path()
            centerLine.move(to: CGPoint(x: 0, y: midY))
            centerLine.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(centerLine, with: .color(lineColor.opacity(0.1)), lineWidth: 0.5)
        }
        .onAppear {
            FIFOReader.shared.start()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
                samples = FIFOReader.shared.getSamples()
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}

// MARK: - FFT Spectrum Computation

/// Computes magnitude spectrum from time-domain samples using vDSP FFT.
/// Uses fixed gain (no auto-normalization) for reactive, ncmpcpp-style output.
enum SpectrumComputer {
    /// Returns `bandCount` magnitude values (0..~1+) from raw PCM samples, log-frequency-scaled.
    /// Values can exceed 1.0 on loud passages — clamp in the renderer if needed.
    static func compute(from samples: [Float], bandCount: Int = 64) -> [Float] {
        guard samples.count >= 64 else { return [Float](repeating: 0, count: bandCount) }

        let log2n = vDSP_Length(log2(Float(samples.count)))
        let n = Int(1 << log2n)
        guard let fft = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return [Float](repeating: 0, count: bandCount)
        }
        defer { vDSP_destroy_fftsetup(fft) }

        // Apply Hann window
        var windowed = [Float](repeating: 0, count: n)
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        vDSP_vmul(Array(samples.prefix(n)), 1, window, 1, &windowed, 1, vDSP_Length(n))

        var realp = [Float](repeating: 0, count: n / 2)
        var imagp = [Float](repeating: 0, count: n / 2)
        var result = [Float](repeating: 0, count: bandCount)

        realp.withUnsafeMutableBufferPointer { realBuf in
            imagp.withUnsafeMutableBufferPointer { imagBuf in
                var splitComplex = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                windowed.withUnsafeBytes { rawBuf in
                    let typedBuf = rawBuf.bindMemory(to: DSPComplex.self)
                    vDSP_ctoz(typedBuf.baseAddress!, 2, &splitComplex, 1, vDSP_Length(n / 2))
                }
                vDSP_fft_zrip(fft, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

                // Linear magnitudes (sqrt of squared magnitudes)
                var magnitudes = [Float](repeating: 0, count: n / 2)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(n / 2))
                // sqrt for amplitude (not power)
                var count32 = Int32(n / 2)
                vvsqrtf(&magnitudes, magnitudes, &count32)

                // Normalize by FFT size
                let scale = 2.0 / Float(n)
                for j in 0..<(n / 2) { magnitudes[j] *= scale }

                // Map to log-frequency bands (like ncmpcpp)
                let nyquist = n / 2
                for i in 0..<bandCount {
                    let ratio0 = Float(i) / Float(bandCount)
                    let ratio1 = Float(i + 1) / Float(bandCount)
                    // Stronger log curve: pow(nyquist, ratio) gives log-frequency spacing
                    let freq0 = max(1, Int(pow(Float(nyquist), ratio0)))
                    let freq1 = max(freq0 + 1, Int(pow(Float(nyquist), ratio1)))

                    let lo = min(freq0, nyquist - 1)
                    let hi = min(freq1, nyquist)
                    guard lo < hi else { continue }

                    // Average magnitudes in this band
                    var avg: Float = 0
                    for j in lo..<hi { avg += magnitudes[j] }
                    avg /= Float(hi - lo)

                    // Fixed gain — amplify so typical music fills the display
                    // sqrt gives a perceptual loudness curve
                    result[i] = sqrt(avg) * 4.0
                }
            }
        }

        return result
    }
}

// MARK: - Spectrum Analyzer View

/// ncmpcpp-style frequency spectrum — reactive bars that fill the screen.
struct SpectrumAnalyzerView: View {
    @State private var smoothBands: [Float] = []
    @State private var peakBands: [Float] = []  // falling peak dots
    @State private var timer: Timer?

    let bandCount: Int
    let barColor: Color
    let backgroundColor: Color

    init(bandCount: Int = 48, barColor: Color = .cyan, backgroundColor: Color = .clear) {
        self.bandCount = bandCount
        self.barColor = barColor
        self.backgroundColor = backgroundColor
    }

    var body: some View {
        Canvas { context, size in
            if backgroundColor != .clear {
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(backgroundColor))
            }

            guard !smoothBands.isEmpty else { return }

            let barWidth = size.width / CGFloat(smoothBands.count)
            let gap: CGFloat = max(1, barWidth * 0.12)

            for (i, raw) in smoothBands.enumerated() {
                let value = min(raw, 1.0)  // clamp for drawing
                let height = CGFloat(value) * size.height
                let x = CGFloat(i) * barWidth

                guard height > 0 else { continue }

                let rect = CGRect(
                    x: x + gap / 2,
                    y: size.height - height,
                    width: barWidth - gap,
                    height: height
                )

                // Color shifts from base to white at top (like ncmpcpp)
                let barPath = Path(roundedRect: rect, cornerRadii: .init(topLeading: 1, topTrailing: 1))
                context.fill(barPath, with: .color(barColor.opacity(0.6 + 0.4 * Double(value))))

                // Brighter cap on top of each bar
                let capHeight: CGFloat = max(2, barWidth * 0.15)
                let capRect = CGRect(
                    x: x + gap / 2,
                    y: size.height - height,
                    width: barWidth - gap,
                    height: capHeight
                )
                context.fill(Path(capRect), with: .color(.white.opacity(0.8)))

                // Falling peak indicator
                if i < peakBands.count {
                    let peakY = CGFloat(min(peakBands[i], 1.0)) * size.height
                    if peakY > height + 3 {
                        let peakRect = CGRect(
                            x: x + gap / 2,
                            y: size.height - peakY,
                            width: barWidth - gap,
                            height: 2
                        )
                        context.fill(Path(peakRect), with: .color(.white.opacity(0.5)))
                    }
                }
            }
        }
        .onAppear {
            smoothBands = [Float](repeating: 0, count: bandCount)
            peakBands = [Float](repeating: 0, count: bandCount)
            FIFOReader.shared.start()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
                let bands = SpectrumComputer.compute(from: FIFOReader.shared.getAccumulatedSamples(), bandCount: bandCount)
                for i in 0..<min(bands.count, smoothBands.count) {
                    // Fast attack, moderate decay — very reactive
                    if bands[i] > smoothBands[i] {
                        smoothBands[i] = bands[i] * 0.8 + smoothBands[i] * 0.2
                    } else {
                        smoothBands[i] = bands[i] * 0.35 + smoothBands[i] * 0.65
                    }
                    // Peak: instant rise, slow gravity fall
                    if smoothBands[i] > peakBands[i] {
                        peakBands[i] = smoothBands[i]
                    } else {
                        peakBands[i] = max(0, peakBands[i] - 0.012)
                    }
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}

// MARK: - Circular Visualizer View

/// Radial spectrum visualizer — mirrored bars radiate outward from a central ring.
struct CircularVisualizerView: View {
    @State private var smoothBands: [Float] = []
    @State private var timer: Timer?

    let bandCount: Int
    let color: Color

    init(bandCount: Int = 90, color: Color = .purple) {
        self.bandCount = bandCount
        self.color = color
    }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let minDim = min(size.width, size.height)
            let innerRadius = minDim * 0.12
            let maxBarLength = minDim * 0.38

            guard !smoothBands.isEmpty else {
                let circle = Path(ellipseIn: CGRect(
                    x: center.x - innerRadius, y: center.y - innerRadius,
                    width: innerRadius * 2, height: innerRadius * 2
                ))
                context.stroke(circle, with: .color(color.opacity(0.3)), lineWidth: 1.5)
                return
            }

            let count = smoothBands.count
            let angleStep = (2 * CGFloat.pi) / CGFloat(count)
            let lineWidth: CGFloat = max(2, (2 * .pi * innerRadius) / CGFloat(count) * 0.7)

            // Draw mirrored bars (both inward and outward)
            for i in 0..<count {
                let angle = CGFloat(i) * angleStep - .pi / 2
                let value = CGFloat(min(smoothBands[i], 1.0))
                let barLength = value * maxBarLength
                let innerBarLength = value * innerRadius * 0.6

                let cosA = cos(angle)
                let sinA = sin(angle)

                // Outward bar
                let outerStart = CGPoint(
                    x: center.x + cosA * innerRadius,
                    y: center.y + sinA * innerRadius
                )
                let outerEnd = CGPoint(
                    x: center.x + cosA * (innerRadius + barLength),
                    y: center.y + sinA * (innerRadius + barLength)
                )

                var outBar = Path()
                outBar.move(to: outerStart)
                outBar.addLine(to: outerEnd)

                // Color gradient based on intensity
                let hue = (Double(i) / Double(count) * 0.3 + 0.75).truncatingRemainder(dividingBy: 1.0)
                let barColor = Color(hue: hue, saturation: 0.7, brightness: 0.5 + 0.5 * Double(value))

                context.stroke(outBar, with: .color(barColor.opacity(0.5 + 0.5 * Double(value))), lineWidth: lineWidth)

                // Glow on loud bars
                if value > 0.4 {
                    context.stroke(outBar, with: .color(barColor.opacity(0.2)), lineWidth: lineWidth + 4)
                }

                // Inward bar (mirror)
                let innerEnd = CGPoint(
                    x: center.x + cosA * (innerRadius - innerBarLength),
                    y: center.y + sinA * (innerRadius - innerBarLength)
                )
                var inBar = Path()
                inBar.move(to: outerStart)
                inBar.addLine(to: innerEnd)
                context.stroke(inBar, with: .color(barColor.opacity(0.3 + 0.4 * Double(value))), lineWidth: lineWidth * 0.7)
            }

            // Glowing inner ring
            let circle = Path(ellipseIn: CGRect(
                x: center.x - innerRadius, y: center.y - innerRadius,
                width: innerRadius * 2, height: innerRadius * 2
            ))
            context.stroke(circle, with: .color(color.opacity(0.5)), lineWidth: 1.5)
            context.stroke(circle, with: .color(color.opacity(0.15)), lineWidth: 4)
        }
        .onAppear {
            smoothBands = [Float](repeating: 0, count: bandCount)
            FIFOReader.shared.start()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
                let bands = SpectrumComputer.compute(from: FIFOReader.shared.getAccumulatedSamples(), bandCount: bandCount)
                for i in 0..<min(bands.count, smoothBands.count) {
                    if bands[i] > smoothBands[i] {
                        smoothBands[i] = bands[i] * 0.8 + smoothBands[i] * 0.2
                    } else {
                        smoothBands[i] = bands[i] * 0.35 + smoothBands[i] * 0.65
                    }
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}

// MARK: - Visualizer Mode

enum VisualizerMode: String, CaseIterable {
    case oscilloscope = "Oscilloscope"
    case spectrum = "Spectrum"
    case circular = "Circular"

    var icon: String {
        switch self {
        case .oscilloscope: "waveform.path"
        case .spectrum: "chart.bar.fill"
        case .circular: "circle.circle"
        }
    }
}
