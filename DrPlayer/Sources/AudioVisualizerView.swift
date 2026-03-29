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
    private let lock = NSLock()

    private init() {}

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
